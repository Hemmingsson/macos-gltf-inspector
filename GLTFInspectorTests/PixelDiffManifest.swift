import Foundation
@testable import GLTFCore

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

    /// `TestModels/References/<name>.png`.
    static func reference(_ name: String) -> URL {
        referencesDirectory.appendingPathComponent("\(name).png")
    }
}

/// The pinned sample set and the committed description of every reference render.
///
/// This one file is the sample list (`scripts/fetch-test-models.sh` downloads exactly these
/// entries at `samples.commit`), the look the page is asked for, the comparison budget, and one
/// complete camera pose per model. Nothing that affects the output is left as
/// a constant in a test file, so changing an assertion means changing a file someone reviews.
struct PixelDiffManifest: Codable, Sendable {
    /// Bumped when the meaning of the file changes, so a stale manifest fails loudly instead of
    /// decoding into something plausible.
    static let currentVersion = 3

    var version: Int
    var samples: SampleSource
    var look: Look
    /// Set from the measured run-to-run noise floor — see `TestModels/References/README.md`.
    var tolerance: PixelDiff.Tolerance
    var entries: [Entry]

    struct SampleSource: Codable, Sendable, Equatable {
        /// `owner/repo` on GitHub.
        var repository: String
        /// Pinned commit every `source` path is resolved at.
        var commit: String
    }

    /// Everything about the look, pinned explicitly rather than inherited from a page default.
    /// Values are in the page's terms.
    struct Look: Codable, Sendable, Equatable {
        /// Square canvas edge, in pixels. Fixed rather than derived — still mode sets
        /// `canvas.width` directly, so `devicePixelRatio` never enters into it.
        var canvasSize: Int
        /// Bundled `.hdr` stem.
        var environment: String
        /// The page's `environmentRotation`. 90 is the Khronos Sample Viewer default view — the
        /// value the goldens have always been rendered at, and what `RenderLook` yaw 0 maps to.
        var environmentRotationDegrees: Double
        /// Camera exposure in stops (0 = the page's linear 1).
        var exposureEV: Double
        var toneMapping: String
        /// `[r, g, b, a]` in 0-1. Transparent: both sides are flattened onto
        /// ``PixelDiff/backdrop`` before comparing.
        var background: [Double]
    }

    struct Entry: Codable, Sendable, Equatable {
        /// Sample name, e.g. `BoomBox`. Also the folder under `TestModels/Khronos samples` and
        /// the reference file's stem.
        var name: String
        /// Upstream folder, relative to the repository root at `samples.commit`.
        var source: String
        /// Files fetched from `source`, primary model first. Sidecars keep their relative path.
        var files: [String]
        /// glTF features the file exercises: `extensionsUsed` plus core feature tags (see
        /// ``PixelDiffSampleFeatures``). Recorded at generation, checked against the file.
        var requires: [String]
        /// Nil until the reference generator has measured the model.
        var camera: Camera?

        var modelURL: URL {
            TestModels.khronosDirectory
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(files.first ?? "\(name).glb")
        }

        var referenceURL: URL {
            PixelDiffPaths.reference(name)
        }
    }

    /// One complete orbit camera, in the page's terms. Field for field the page's `CameraPose`,
    /// kept here so the manifest decodes without `RendererWebKit`. Angles are degrees, `yfov` is
    /// radians.
    struct Camera: Codable, Sendable, Equatable {
        var azimuth: Double
        var elevation: Double
        var distance: Double
        /// Scene-space point the camera looks at.
        var target: [Double]
        var yfov: Double
        var znear: Double
        var zfar: Double

        var isFinite: Bool {
            ([azimuth, elevation, distance, yfov, znear, zfar] + target).allSatisfy(\.isFinite)
        }
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

/// What a sample exercises, read from its JSON.
///
/// Recorded in the manifest (`requires`) so what each golden exercises is reviewable without
/// opening every file; a core test keeps the record honest.
enum PixelDiffSampleFeatures {
    static func json(of url: URL) throws -> [String: Any] {
        try GLBBox.peekDocumentJSON(from: url)
    }

    /// `extensionsUsed`, plus `core:` tags for core features a renderer can get wrong.
    static func derive(from json: [String: Any]) -> [String] {
        var features = Set((json["extensionsUsed"] as? [String]) ?? [])
        let meshes = (json["meshes"] as? [[String: Any]]) ?? []
        let primitives = meshes.flatMap { ($0["primitives"] as? [[String: Any]]) ?? [] }
        let attributes = Set(primitives.flatMap { (($0["attributes"] as? [String: Any]) ?? [:]).keys })
        if attributes.contains("COLOR_0") { features.insert("core:vertexColor") }
        if attributes.contains("TEXCOORD_1") { features.insert("core:texcoord1") }
        if primitives.contains(where: { $0["targets"] != nil }) { features.insert("core:morph") }
        if !((json["skins"] as? [Any]) ?? []).isEmpty { features.insert("core:skin") }
        if !((json["animations"] as? [Any]) ?? []).isEmpty { features.insert("core:animation") }
        let materials = (json["materials"] as? [[String: Any]]) ?? []
        if materials.contains(where: { ($0["alphaMode"] as? String) == "BLEND" }) {
            features.insert("core:alphaBlend")
        }
        if materials.contains(where: { ($0["alphaMode"] as? String) == "MASK" }) {
            features.insert("core:alphaMask")
        }
        return features.sorted()
    }
}

/// Whether the reference generator (or the noise-floor measurement) was asked for.
///
/// A file rather than an environment variable, because `xcodebuild test` does not forward the
/// invoking shell's environment to the test process — a variable set on the command line simply
/// never arrives, and the generator would look like it ran and did nothing.
/// `scripts/regenerate-pixel-references.sh` creates and removes the sentinels.
///
/// Free-standing rather than a member of the generator suite: `@Test(.enabled(if:))` evaluates
/// its condition off the main actor.
enum PixelDiffRegeneration {
    static let sentinelURL = PixelDiffPaths.referencesDirectory
        .appendingPathComponent("REGENERATE")
    static let noiseSentinelURL = PixelDiffPaths.referencesDirectory
        .appendingPathComponent("MEASURE_NOISE")

    static var isRequested: Bool {
        FileManager.default.fileExists(atPath: sentinelURL.path)
    }

    static var isNoiseMeasurementRequested: Bool {
        FileManager.default.fileExists(atPath: noiseSentinelURL.path)
    }
}
