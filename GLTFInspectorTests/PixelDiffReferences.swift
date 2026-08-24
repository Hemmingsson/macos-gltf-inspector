import CoreGraphics
import Foundation
@testable import GLTFInspector

/// Where the committed references live and where failures get written.
enum PixelDiffPaths {
    static let referencesDirectory = TestFixtures.url("TestModels/References")
    static let manifestURL = referencesDirectory.appendingPathComponent("manifest.json")

    /// Actual, expected and difference images for anything that failed. A red bar with nothing
    /// to look at is not actionable, so every mismatch leaves three files behind.
    static var outputDirectory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["GLB_PIXEL_DIFF_OUT"]
            ?? "/tmp/GLTFInspector-pixel-diff")
    }

    static func reference(_ fileName: String) -> URL {
        referencesDirectory.appendingPathComponent(fileName)
    }
}

/// The committed description of every reference render.
///
/// Everything the harness controls is written down here rather than left as a constant in a
/// test file: canvas size, environment, tone mapping, the comparison budget, and one complete
/// camera pose per model. A change to any of them is a change to the assertions, and belongs in
/// a diff someone reviews.
struct PixelDiffManifest: Codable, Sendable {
    /// Bumped when the meaning of the file changes, so a stale manifest fails loudly instead of
    /// decoding into something plausible.
    static let currentVersion = 1

    var version: Int
    /// Square canvas edge, in pixels. Fixed rather than derived — still mode sets
    /// `canvas.width` directly, so `devicePixelRatio` never enters into it.
    var canvasSize: Int
    var environment: String
    var toneMapping: String
    var tolerance: PixelDiff.Tolerance
    var entries: [Entry]

    struct Entry: Codable, Sendable, Equatable {
        /// Sample name, e.g. `BoomBox`. Also the reference file's stem.
        var name: String
        /// Model path relative to the repo root.
        var model: String
        /// Reference PNG name, relative to `TestModels/References`.
        var reference: String
        var camera: CameraPose

        var modelURL: URL { TestFixtures.url(model) }
        var referenceURL: URL { PixelDiffPaths.reference(reference) }
    }

    enum LoadFailure: Error, CustomStringConvertible {
        case missing(URL)
        case unreadable(URL, any Error)
        case wrongVersion(found: Int, expected: Int)

        var description: String {
            switch self {
            case .missing(let url):
                """
                No pixel-diff manifest at \(url.path). \
                Regenerate with: \(PixelDiffManifest.regenerationCommand)
                """
            case .unreadable(let url, let error):
                "Could not decode \(url.path): \(error)"
            case .wrongVersion(let found, let expected):
                "Manifest is version \(found), this build expects \(expected)"
            }
        }
    }

    static let regenerationCommand = "./scripts/regenerate-pixel-references.sh"

    static func load() throws -> Self {
        let url = PixelDiffPaths.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadFailure.missing(url)
        }
        let manifest: Self
        do {
            manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            throw LoadFailure.unreadable(url, error)
        }
        guard manifest.version == currentVersion else {
            throw LoadFailure.wrongVersion(found: manifest.version, expected: currentVersion)
        }
        return manifest
    }

    func write() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(
            at: PixelDiffPaths.referencesDirectory,
            withIntermediateDirectories: true
        )
        try encoder.encode(self).write(to: PixelDiffPaths.manifestURL)
    }
}

/// Whether the reference generator was asked for.
///
/// A file rather than an environment variable, because `xcodebuild test` does not forward the
/// invoking shell's environment to the test process — a variable set on the command line simply
/// never arrives, and the generator would look like it ran and did nothing.
/// `scripts/regenerate-pixel-references.sh` creates and removes the sentinel.
///
/// Free-standing rather than a member of the generator suite: `@Test(.enabled(if:))` evaluates
/// its condition off the main actor.
enum PixelDiffRegeneration {
    static let sentinelURL = PixelDiffPaths.referencesDirectory
        .appendingPathComponent("REGENERATE")

    static var isRequested: Bool {
        FileManager.default.fileExists(atPath: sentinelURL.path)
    }
}

/// The one place a reference render is produced.
///
/// Generation and verification both go through here. If they did not, a difference between the
/// two paths — a host reused in one and not the other, a command sent in a different order —
/// would show up as every model failing, and the natural response would be to widen the
/// tolerance until it stopped.
@MainActor
enum PixelDiffRenderer {
    /// Orbit applied to every reference, so models are not seen straight down their front axis
    /// where a swapped depth test or a missing face can hide. Negative elevation looks down at
    /// the model — the page's `rotAroundX` grows as the camera swings under it.
    static let azimuth: Double = 25
    static let elevation: Double = -18
    /// Breathing room around the bounding sphere, so a model that grows slightly does not start
    /// clipping the frame edge and turn a small regression into an unreadable one.
    static let distancePadding: Double = 1.06

    static let canvasSize = 512
    static let environment = "neutral"
    static let toneMapping = "Khronos PBR Neutral"

    static func makeHost(manifest: PixelDiffManifest) async throws -> WebRendererHost {
        let host = try WebRendererHost(mode: .still, timeout: .seconds(60))
        try await host.start(size: manifest.canvasSize)
        try await host.setEnvironment(named: manifest.environment)
        try await host.send { .setToneMapping(id: $0, name: manifest.toneMapping) }
        return host
    }

    /// Loads a model and renders it from an already-recorded pose.
    static func render(
        _ entry: PixelDiffManifest.Entry,
        on host: WebRendererHost
    ) async throws -> CGImage {
        _ = try await host.load(model: entry.modelURL)
        try await host.setCameraPose(entry.camera)
        return try await host.renderStill()
    }

    /// Loads a model, measures it, and freezes a complete camera pose around it.
    ///
    /// Only the *measurement* comes from the renderer. The framing is computed here, from the
    /// scene bounds, for two reasons:
    ///
    /// - `fitDistanceToExtents` frames the larger of the scene's X and Y extents and ignores Z
    ///   entirely, so a model that is deep rather than wide runs out of the frame.
    /// - It frames for a head-on view. Every reference is orbited, and a box that just fits
    ///   head on does not fit off axis.
    ///
    /// Distance is derived from the sphere enclosing the scene instead, which has no
    /// orientation to get wrong: at `radius / sin(yfov / 2)` the model spans the frame at any
    /// azimuth and elevation. The result is recorded, so verification replays numbers rather
    /// than re-deriving them, and a change to either heuristic cannot re-aim the camera.
    static func recordPose(for model: URL, on host: WebRendererHost) async throws -> CameraPose {
        _ = try await host.load(model: model)
        let measured = try await host.cameraState()

        let radius = measured.boundingRadius
        let yfov = measured.pose.yfov
        let distance = radius / sin(yfov / 2) * distancePadding

        // Enough depth range to hold the whole model on both sides of the target, clamped the
        // way the renderer clamps its own near plane to keep the ratio out of z-fighting range.
        let zfar = distance + radius * 2
        return CameraPose(
            azimuth: azimuth,
            elevation: elevation,
            distance: distance,
            target: measured.sceneCenter,
            yfov: yfov,
            znear: max(distance - radius * 2, zfar / 10_000),
            zfar: zfar
        )
    }
}
