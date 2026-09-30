import CoreGraphics
import Foundation
import Testing
@testable import RendererWebKit

/// The WebKit renderer in the pixel-diff harness: `WebRendererHost` in still mode. The comparator,
/// manifest and loops are renderer-neutral (`PixelDiff*.swift` at the test root).
@MainActor
enum PixelDiffWebKit {
    /// Orbit applied to every reference, so models are not seen straight down their front axis
    /// where a swapped depth test or a missing face can hide. Negative elevation looks down at
    /// the model — the page's `rotAroundX` grows as the camera swings under it.
    static let azimuth: Double = 25
    static let elevation: Double = -18
    /// Breathing room around the bounding sphere, so a model that grows slightly does not start
    /// clipping the frame edge and turn a small regression into an unreadable one.
    static let distancePadding: Double = 1.06

    /// A render function over one host, set up once for a whole pass over the manifest.
    static func make(manifest: PixelDiffManifest) async throws -> PixelDiffRun.Render {
        let host = try await makeHost(manifest: manifest)
        return { entry in try await render(entry, on: host) }
    }

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
        let camera = try PixelDiffRun.camera(of: entry)
        _ = try await host.load(model: entry.modelURL)
        try await host.setCameraPose(CameraPose(camera))
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
    static func recordPose(
        for model: URL,
        on host: WebRendererHost
    ) async throws -> PixelDiffManifest.Camera {
        _ = try await host.load(model: model)
        let measured = try await host.cameraState()

        let radius = measured.boundingRadius
        let yfov = measured.pose.yfov
        let distance = radius / sin(yfov / 2) * distancePadding

        // Enough depth range to hold the whole model on both sides of the target, clamped the
        // way the renderer clamps its own near plane to keep the ratio out of z-fighting range.
        let zfar = distance + radius * 2
        return PixelDiffManifest.Camera(
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

extension CameraPose {
    /// The manifest camera is the page's pose, field for field.
    init(_ camera: PixelDiffManifest.Camera) {
        self.init(
            azimuth: camera.azimuth,
            elevation: camera.elevation,
            distance: camera.distance,
            target: camera.target,
            yfov: camera.yfov,
            znear: camera.znear,
            zfar: camera.zfar
        )
    }
}

extension PixelDiffManifest.Camera {
    init(_ pose: CameraPose) {
        self.init(
            azimuth: pose.azimuth,
            elevation: pose.elevation,
            distance: pose.distance,
            target: pose.target,
            yfov: pose.yfov,
            znear: pose.znear,
            zfar: pose.zfar
        )
    }
}

/// The safety net for the web renderer: every pinned sample rendered and compared against
/// `TestModels/References/webkit/`.
@MainActor
@Suite(.serialized)
struct PixelDiffWebKitTests {
    @Test func everySampleMatchesItsReference() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.expectEverySampleMatches(
            .webkit,
            manifest: manifest,
            render: try await PixelDiffWebKit.make(manifest: manifest)
        )
    }

    @Test func everyReferenceImageIsPresentAndTheRightShape() throws {
        try PixelDiffRun.expectEveryReferenceIsPresent(.webkit)
    }

    /// The premise of the whole harness. If the renderer does not produce the same pixels twice
    /// in a row, no committed reference means anything.
    @Test func renderingTheSameModelTwiceProducesTheSamePixels() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        let host = try await PixelDiffWebKit.makeHost(manifest: manifest)

        let first = try PixelDiff.raster(from: try await PixelDiffWebKit.render(entry, on: host))
        let second = try PixelDiff.raster(from: try await PixelDiffWebKit.render(entry, on: host))

        let (metrics, _) = try PixelDiff.compare(
            first, to: second, tolerance: try manifest.tolerance(for: .webkit)
        )
        #expect(metrics.maxChannelDifference == 0, "renderer is not deterministic: \(metrics.summary())")
    }

    /// `everySampleMatchesItsReference` renders every model through one web view to keep the
    /// suite quick. That only holds if a model leaves no trace on the next one — otherwise the
    /// references would encode the sample ordering, and reordering the manifest would break
    /// every test downstream of the change.
    @Test func aHostThatAlreadyDrewAnotherModelDrawsTheSame() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(manifest.entries.count >= 2)
        let subject = try #require(manifest.entries.last)
        let predecessor = try #require(manifest.entries.first)

        let clean = try await PixelDiffWebKit.makeHost(manifest: manifest)
        let alone = try PixelDiff.raster(from: try await PixelDiffWebKit.render(subject, on: clean))

        let reused = try await PixelDiffWebKit.makeHost(manifest: manifest)
        _ = try await PixelDiffWebKit.render(predecessor, on: reused)
        let afterAnother = try PixelDiff.raster(
            from: try await PixelDiffWebKit.render(subject, on: reused)
        )

        let (metrics, _) = try PixelDiff.compare(
            afterAnother, to: alone, tolerance: try manifest.tolerance(for: .webkit)
        )
        #expect(
            metrics.maxChannelDifference == 0,
            "\(subject.name) renders differently after \(predecessor.name): \(metrics.summary())"
        )
    }
}

/// Rewrites the web references and — because every renderer replays them — the recorded camera
/// poses and `requires` features in the manifest. Off unless asked for: this is a generator, not
/// an assertion, and running it as part of a normal suite would make the tests agree with
/// whatever the renderer currently does.
///
///     ./scripts/regenerate-pixel-references.sh [webkit]
///
/// The manifest's entry list is the pinned sample set: the generator never adds or drops
/// entries. Then look at the PNGs before committing them. They are the assertions; a wrong one
/// bakes in a wrong answer for good.
@MainActor
struct PixelDiffWebKitRegeneration {
    @Test(.enabled(if: PixelDiffRegeneration.isRequested(for: .webkit)))
    func regenerate() async throws {
        var manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "no pinned samples to render")

        let host = try await PixelDiffWebKit.makeHost(manifest: manifest)
        for index in manifest.entries.indices {
            let model = manifest.entries[index].modelURL
            manifest.entries[index].camera = try await PixelDiffWebKit.recordPose(for: model, on: host)
            manifest.entries[index].requires = PixelDiffSampleFeatures.derive(
                from: try PixelDiffSampleFeatures.json(of: model)
            )
        }
        try manifest.write()

        try await PixelDiffRun.regenerate(
            .webkit, manifest: manifest, render: try await PixelDiffWebKit.make(manifest: manifest)
        )
    }

    /// `./scripts/regenerate-pixel-references.sh --measure-noise`
    @Test(.enabled(if: PixelDiffRegeneration.isNoiseMeasurementRequested))
    func measureNoise() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.measureNoise(.webkit, manifest: manifest) {
            try await PixelDiffWebKit.make(manifest: manifest)
        }
    }
}
