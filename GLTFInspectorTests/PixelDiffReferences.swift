import CoreGraphics
import Foundation
import RealityKit
import simd
@testable import GLTFInspector

/// The renderers that keep their own goldens. Never compared against each other — each has its
/// own tone mapper and light units, so a cross-renderer pixel gate would only measure that.
enum PixelDiffRendererKind: String, CaseIterable, Codable, Sendable {
    case webkit
    case realitykit
}

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

    /// `TestModels/References/<renderer>/<name>.png`.
    static func reference(_ name: String, renderer: PixelDiffRendererKind) -> URL {
        referencesDirectory
            .appendingPathComponent(renderer.rawValue, isDirectory: true)
            .appendingPathComponent("\(name).png")
    }
}

/// The pinned sample set and the committed description of every reference render.
///
/// This one file is the sample list (`scripts/fetch-test-models.sh` downloads exactly these
/// entries at `samples.commit`), the look every renderer is asked for, the comparison budget per
/// renderer, and one complete camera pose per model. Nothing that affects the output is left as
/// a constant in a test file, so changing an assertion means changing a file someone reviews.
struct PixelDiffManifest: Codable, Sendable {
    /// Bumped when the meaning of the file changes, so a stale manifest fails loudly instead of
    /// decoding into something plausible.
    static let currentVersion = 2

    var version: Int
    var samples: SampleSource
    var look: Look
    /// Keyed by ``PixelDiffRendererKind`` raw value. Set from the measured run-to-run noise
    /// floor — see `TestModels/References/README.md`.
    var tolerances: [String: PixelDiff.Tolerance]
    var entries: [Entry]

    struct SampleSource: Codable, Sendable, Equatable {
        /// `owner/repo` on GitHub.
        var repository: String
        /// Pinned commit every `source` path is resolved at.
        var commit: String
    }

    /// Everything about the look, pinned explicitly rather than inherited from a renderer
    /// default. Values are in the WebKit page's terms; RealityKit's mapping of each is in
    /// ``PixelDiffRealityKit``.
    struct Look: Codable, Sendable, Equatable {
        /// Square canvas edge, in pixels. Fixed rather than derived — still mode sets
        /// `canvas.width` directly, so `devicePixelRatio` never enters into it.
        var canvasSize: Int
        /// Bundled `.hdr` stem.
        var environment: String
        /// The page's `environmentRotation`. 90 is the Khronos Sample Viewer default view — the
        /// value the web goldens have always been rendered at, and what a future `RenderLook`
        /// yaw of 0 maps to.
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
        var camera: CameraPose?

        var modelURL: URL {
            TestModels.khronosDirectory
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(files.first ?? "\(name).glb")
        }

        func referenceURL(for renderer: PixelDiffRendererKind) -> URL {
            PixelDiffPaths.reference(name, renderer: renderer)
        }
    }

    enum LoadFailure: Error, CustomStringConvertible {
        case missing(URL)
        case unreadable(URL, any Error)
        case wrongVersion(found: Int, expected: Int)
        case noTolerance(PixelDiffRendererKind)

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
            case .noTolerance(let renderer):
                "Manifest has no tolerance for \(renderer.rawValue)"
            }
        }
    }

    static let regenerationCommand = "./scripts/regenerate-pixel-references.sh"

    func tolerance(for renderer: PixelDiffRendererKind) throws -> PixelDiff.Tolerance {
        guard let tolerance = tolerances[renderer.rawValue] else {
            throw LoadFailure.noTolerance(renderer)
        }
        return tolerance
    }

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
/// Recorded in the manifest (`requires`) so a later per-renderer capability set can decide which
/// entries run without opening every file; a core test keeps the record honest.
enum PixelDiffSampleFeatures {
    static func json(of url: URL) throws -> [String: Any] {
        url.pathExtension.lowercased() == "glb"
            ? try GLBBox.peekJSON(from: url)
            : try GLBBox.parseJSON(Data(contentsOf: url))
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

    /// Renderers named in the sentinel (whitespace-separated); an empty file means all of them.
    static var requestedRenderers: [PixelDiffRendererKind] {
        let text = (try? String(contentsOf: sentinelURL, encoding: .utf8)) ?? ""
        let named = text.split(whereSeparator: \.isWhitespace).compactMap {
            PixelDiffRendererKind(rawValue: String($0))
        }
        return named.isEmpty ? PixelDiffRendererKind.allCases : named
    }
}

/// Produces one reference render per renderer. Generation and verification both go through
/// here. If they did not, a difference between the two paths — a host reused in one and not the
/// other, a command sent in a different order — would show up as every model failing, and the
/// natural response would be to widen the tolerance until it stopped.
@MainActor
enum PixelDiffRendering {
    typealias Render = @MainActor (PixelDiffManifest.Entry) async throws -> CGImage

    /// A render function for `renderer`, set up once for a whole pass over the manifest.
    static func make(
        _ renderer: PixelDiffRendererKind,
        manifest: PixelDiffManifest
    ) async throws -> Render {
        switch renderer {
        case .webkit:
            let host = try await PixelDiffRenderer.makeHost(manifest: manifest)
            return { entry in try await PixelDiffRenderer.render(entry, on: host) }
        case .realitykit:
            return { entry in try await PixelDiffRealityKit.render(entry, look: manifest.look) }
        }
    }

    enum Failure: Error, CustomStringConvertible {
        case noCamera(String)

        var description: String {
            switch self {
            case .noCamera(let name):
                "\(name) has no recorded camera pose. Regenerate with: \(PixelDiffManifest.regenerationCommand)"
            }
        }
    }

    static func camera(of entry: PixelDiffManifest.Entry) throws -> CameraPose {
        guard let camera = entry.camera else { throw Failure.noCamera(entry.name) }
        return camera
    }
}

/// The WebKit renderer: `WebRendererHost` in still mode.
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

    /// Applies the whole pinned look. Exposure and environment rotation are sent even though
    /// they equal the page defaults, so a change of default cannot move the goldens. The
    /// background needs no command: the page's `clearColor` is fixed transparent and the
    /// comparison flattens onto ``PixelDiff/backdrop``.
    static func makeHost(manifest: PixelDiffManifest) async throws -> WebRendererHost {
        let look = manifest.look
        let host = try WebRendererHost(mode: .still, timeout: .seconds(60))
        try await host.start(size: look.canvasSize)
        try await host.setEnvironment(named: look.environment)
        try await host.send { .setToneMapping(id: $0, name: look.toneMapping) }
        try await host.send { .setExposure(id: $0, stops: look.exposureEV) }
        try await host.send {
            .setEnvironmentRotation(id: $0, degrees: look.environmentRotationDegrees)
        }
        return host
    }

    /// Loads a model and renders it from an already-recorded pose.
    static func render(
        _ entry: PixelDiffManifest.Entry,
        on host: WebRendererHost
    ) async throws -> CGImage {
        let camera = try PixelDiffRendering.camera(of: entry)
        _ = try await host.load(model: entry.modelURL)
        try await host.setCameraPose(camera)
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

/// The RealityKit renderer: the shipping `EntityLoader.loadThumbnail` → `StillRenderer` path,
/// posed from the same manifest camera as the web goldens.
///
/// Look mapping (RealityKit is never compared against the web; this only says what is pinned):
///
/// | Manifest | RealityKit | Status |
/// | --- | --- | --- |
/// | `environment` | `AppLook` catalog of that name, IBL on | pinned, not read from the user's `look.json` |
/// | `environmentRotationDegrees` | IBL yaw ``environmentYaw`` (native 0) | offset vs Khronos unmeasured (seam 5) |
/// | `exposureEV` | `sessionIBLExponent` — IBL only, plus −2 EV file-light policy | IBL-only exposure (research G2) |
/// | `toneMapping` | system tone map | PBR Neutral not available (decision 2 → B) |
/// | `background` | opaque ``PixelDiff/backdrop`` grey | `StillRenderer` output carries no alpha |
@MainActor
enum PixelDiffRealityKit {
    /// RealityKit's native IBL orientation, as the app ships it. The offset to the Khronos
    /// default view is measured in seam 5; until then the goldens pin today's behaviour.
    static let environmentYaw: Float = 0

    static func render(
        _ entry: PixelDiffManifest.Entry,
        look: PixelDiffManifest.Look
    ) async throws -> CGImage {
        let camera = try PixelDiffRendering.camera(of: entry)
        let model = try await EntityLoader.loadThumbnail(from: entry.modelURL)
        let still = try await StillRenderer(
            root: model.entity,
            cameraPose: stillPose(camera),
            width: look.canvasSize,
            height: look.canvasSize,
            background: CGColor(
                srgbRed: CGFloat(PixelDiff.backdrop.r) / 255,
                green: CGFloat(PixelDiff.backdrop.g) / 255,
                blue: CGFloat(PixelDiff.backdrop.b) / 255,
                alpha: 1
            ),
            intensityExponent: PreviewEmissive.sessionIBLExponent(
                dimStudioForFileLights: model.studioIBLExponent != 0,
                exposureEV: Float(look.exposureEV)
            ),
            environmentYaw: environmentYaw,
            look: AppLook(useEnvironmentMap: true, catalogRaw: look.environment, customFileName: nil)
        )
        return try await still.capture()
    }

    /// The page's orbit camera, in RealityKit terms. Khronos `UserCamera.setRotation` builds
    /// `Ry(azimuth) * Rx(elevation)` and places the eye `distance` along that rotation's +Z from
    /// the target; both engines look down −Z with +Y up, and the converter keeps glTF axes.
    static func stillPose(_ pose: CameraPose) -> StillCameraPose {
        let yaw = simd_quatf(angle: Float(pose.azimuth * .pi / 180), axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(pose.elevation * .pi / 180), axis: [1, 0, 0])
        let orientation = yaw * pitch
        let target = SIMD3<Float>(pose.target.map(Float.init))
        return StillCameraPose(
            position: target + orientation.act([0, 0, Float(pose.distance)]),
            orientation: orientation,
            projection: .perspective(
                fieldOfViewDegrees: Float(pose.yfov * 180 / .pi),
                near: Float(pose.znear),
                far: Float(pose.zfar)
            )
        )
    }
}
