import CoreGraphics
import Foundation
import GLTFCore
import simd
import Testing
@testable import Renderer

/// The renderer in the pixel-diff harness. The comparator, manifest and loops are in the other
/// `PixelDiff*.swift` files.
///
/// The committed references were rendered by the Khronos glTF Sample Renderer itself (its web
/// page, which this app used to embed), so these tests hold the Metal port to Khronos's output.
@MainActor
enum PixelDiffMetal {
    /// Orbit applied to every sample when recording its pose, so models are not seen straight
    /// down their front axis where a swapped depth test or a missing face can hide.
    static let azimuth: Double = 25
    static let elevation: Double = -18
    /// Breathing room around the bounding sphere, so a model that grows slightly does not start
    /// clipping the frame edge.
    static let distancePadding: Double = 1.06

    /// A render function over one renderer, set up once for a whole pass over the manifest.
    static func make(manifest: PixelDiffManifest) async throws -> PixelDiffRun.Render {
        let renderer = try MetalRenderer()
        let options = ViewOptions(look: try renderLook(manifest.look))
        return { entry in
            let camera = try PixelDiffRun.camera(of: entry)
            try await renderer.load(url: entry.modelURL)
            let size = manifest.look.canvasSize
            return try renderer.image(options, pose: MetalCameraPose(camera), width: size, height: size)
        }
    }

    /// The manifest's pinned look. Its rotation is Khronos's `environmentRotation`, where 90 is
    /// the Sample Viewer's default view and `RenderLook` yaw 0.
    static func renderLook(_ look: PixelDiffManifest.Look) throws -> RenderLook {
        let background = look.background
        return RenderLook(
            exposureEV: look.exposureEV,
            environmentIntensity: 1,
            environmentYawDegrees: look.environmentRotationDegrees - 90,
            environment: try #require(LightingEnvironment(rawValue: look.environment)),
            toneMapping: try #require(RenderLook.ToneMapping(rawValue: look.toneMapping)),
            background: RenderLook.Color(red: background[0], green: background[1], blue: background[2], alpha: background[3])
        )
    }

    /// Loads a model, measures it, and freezes a complete camera pose around it.
    ///
    /// Only the measurement comes from the renderer. Distance comes from the sphere enclosing
    /// the scene, which has no orientation to get wrong: at `radius / sin(yfov / 2)` the model
    /// spans the frame at any angle. The result is recorded, so verification replays numbers
    /// and a change to the fit heuristic cannot re-aim the camera.
    static func recordPose(for model: URL, look: RenderLook) async throws -> PixelDiffManifest.Camera {
        let view = ModelView(renderer: try MetalRenderer())
        try await view.apply(ViewOptions(look: look))
        try await view.load(model)
        let camera = view.camera
        let center = (camera.sceneMin + camera.sceneMax) / 2
        let radius = simd_length(camera.sceneMax - camera.sceneMin) / 2
        let distance = radius / sin(camera.yfov / 2) * distancePadding
        let zfar = distance + radius * 2
        return PixelDiffManifest.Camera(
            azimuth: azimuth, elevation: elevation, distance: distance,
            target: [center.x, center.y, center.z], yfov: camera.yfov,
            znear: max(distance - radius * 2, zfar / 10_000), zfar: zfar
        )
    }
}

extension MetalCameraPose {
    init(_ camera: PixelDiffManifest.Camera) {
        self.init(
            azimuth: camera.azimuth, elevation: camera.elevation, distance: camera.distance,
            target: SIMD3(Float(camera.target[0]), Float(camera.target[1]), Float(camera.target[2])),
            yfov: camera.yfov, znear: camera.znear, zfar: camera.zfar
        )
    }
}

/// Every pinned Khronos sample rendered and compared against `TestModels/References/`.
@MainActor
@Suite(.serialized)
struct PixelDiffMetalTests {
    @Test func everySampleMatchesItsKhronosReference() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.expectEverySampleMatches(
            manifest: manifest,
            render: try await PixelDiffMetal.make(manifest: manifest)
        )
    }

    @Test func everyReferenceImageIsPresentAndTheRightShape() throws {
        try PixelDiffRun.expectEveryReferenceIsPresent()
    }

    /// The premise of the harness: the same model drawn twice gives the same pixels.
    @Test func renderingTheSameModelTwiceProducesTheSamePixels() async throws {
        let manifest = try PixelDiffManifest.load()
        let entry = try #require(manifest.entries.first)
        let render = try await PixelDiffMetal.make(manifest: manifest)
        let first = try PixelDiff.raster(from: try await render(entry))
        let second = try PixelDiff.raster(from: try await render(entry))
        let (metrics, _) = try PixelDiff.compare(first, to: second, tolerance: manifest.tolerance)
        #expect(metrics.maxChannelDifference == 0, "renderer is not deterministic: \(metrics.summary())")
    }

    /// The suite draws every model with one renderer. That only holds if a model leaves no trace
    /// on the next one; otherwise the references would encode the sample order.
    @Test func aRendererThatAlreadyDrewAnotherModelDrawsTheSame() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(manifest.entries.count >= 2)
        let subject = try #require(manifest.entries.last)
        let predecessor = try #require(manifest.entries.first)

        let alone = try PixelDiff.raster(from: try await PixelDiffMetal.make(manifest: manifest)(subject))
        let reused = try await PixelDiffMetal.make(manifest: manifest)
        _ = try await reused(predecessor)
        let afterAnother = try PixelDiff.raster(from: try await reused(subject))

        let (metrics, _) = try PixelDiff.compare(afterAnother, to: alone, tolerance: manifest.tolerance)
        #expect(metrics.maxChannelDifference == 0,
                "\(subject.name) renders differently after \(predecessor.name): \(metrics.summary())")
    }
}

/// What the 33 samples do not cover: overlays, view modes, file cameras, scenes and the other
/// looks, through `ModelView` with its own fit and an orbit to 30°/−20°. The references in
/// `TestModels/References/Features/` were rendered by the Khronos page the same way.
@MainActor
@Suite(.serialized)
struct FeatureReferenceTests {
    static let size = 256
    static let directory = PixelDiffPaths.referencesDirectory.appendingPathComponent("Features")
    static var boomBox: URL { TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb") }

    static var cases: [(name: String, model: URL, options: ViewOptions)] {
        var cases: [(name: String, model: URL, options: ViewOptions)] = [
            ("floor", TestFixtures.offcenter, ViewOptions(showsFloor: true)),
            ("origin", TestFixtures.offcenter, ViewOptions(isCentered: false)),
            ("selection", TestFixtures.offcenter, ViewOptions(selectedNodeIndex: 0)),
            ("all-overlays", TestFixtures.cube, ViewOptions(showsFloor: true, isCentered: false, selectedNodeIndex: 0)),
            ("wireframe", TestFixtures.cube, ViewOptions(viewMode: .wireframe)),
            ("orthographic", TestFixtures.cube, ViewOptions(isOrthographic: true)),
            ("narrow-fov", TestFixtures.cube, ViewOptions(fieldOfView: 25)),
            ("basecolor-only", TestFixtures.missingChannels, ViewOptions()),
            ("file-camera-1", TestFixtures.cameras, ViewOptions(fileCameraNodeIndex: 1)),
            ("file-camera-2", TestFixtures.cameras, ViewOptions(fileCameraNodeIndex: 2)),
            ("second-scene", TestFixtures.multiScene, ViewOptions(sceneIndex: 1)),
            ("punctual-lights", TestFixtures.lights, ViewOptions()),
        ]
        for channel in RenderViewMode.Channel.allCases {
            cases.append(("basecolor-only-\(channel)", TestFixtures.missingChannels, ViewOptions(viewMode: .channel(channel))))
            cases.append(("BoomBox-\(channel)", boomBox, ViewOptions(viewMode: .channel(channel))))
        }
        func look(_ edit: (inout RenderLook) -> Void) -> ViewOptions {
            var look = RenderLook.standard
            edit(&look)
            return ViewOptions(look: look)
        }
        cases += [
            ("BoomBox-field", boomBox, look { $0.environment = .field }),
            ("BoomBox-studio", boomBox, look { $0.environment = .colorfulStudio }),
            ("BoomBox-aces-hill", boomBox, look { $0.toneMapping = .acesHill }),
            ("BoomBox-aces-narkowicz", boomBox, look { $0.toneMapping = .acesNarkowicz }),
            ("BoomBox-linear", boomBox, look { $0.toneMapping = .none }),
            ("BoomBox-exposure-yaw", boomBox, look { $0.exposureEV = 1; $0.environmentYawDegrees = 90 }),
        ]
        return cases
    }

    static func render(_ model: URL, _ options: ViewOptions) async throws -> CGImage {
        let view = ModelView(renderer: try MetalRenderer())
        view.frame = CGRect(x: 0, y: 0, width: size, height: size)
        try await view.apply(options)
        try await view.load(model)
        view.orbit(azimuth: 30, elevation: -20)
        return try view.image(width: size, height: size)
    }

    @Test func everyFeatureMatchesItsKhronosReference() async throws {
        let tolerance = try PixelDiffManifest.load().tolerance
        var failures: [String] = []
        for (name, model, options) in Self.cases {
            let expected = try PixelDiff.raster(contentsOf: Self.directory.appendingPathComponent("\(name).png"))
            let actual = try PixelDiff.raster(from: try await Self.render(model, options))
            let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: tolerance)
            print("feature \(name): \(metrics.summary())")
            if case .differs(let reasons) = verdict {
                failures.append(name)
                let report = try PixelDiffReport.write(name: "feature-\(name)", actual: actual, expected: expected)
                Issue.record(Comment(rawValue: "\(name): \(reasons.joined(separator: "; "))\n\(report)"))
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(Self.cases.count) features differ: \(failures)")
    }

    @Test func everyFeatureReferenceHasACase() throws {
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: Self.directory.path).filter { $0.hasSuffix(".png") })
        let expected = Set(Self.cases.map { "\($0.name).png" })
        #expect(onDisk == expected, "stray: \(onDisk.subtracting(expected).sorted()), missing: \(expected.subtracting(onDisk).sorted())")
    }
}

/// Rewrites the sample poses, `requires` features and reference PNGs, and the feature PNGs,
/// from the Metal renderer. Off unless asked for (`./scripts/regenerate-pixel-references.sh`):
/// it is a generator, not an assertion. Regenerated references stop being Khronos's output and
/// become this renderer's, so look at every changed PNG against the Khronos Sample Viewer
/// before committing.
@MainActor
struct PixelDiffRegenerationTests {
    @Test(.enabled(if: PixelDiffRegeneration.isRequested))
    func regenerate() async throws {
        var manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "no pinned samples to render")
        let look = try PixelDiffMetal.renderLook(manifest.look)
        for index in manifest.entries.indices {
            let model = manifest.entries[index].modelURL
            manifest.entries[index].camera = try await PixelDiffMetal.recordPose(for: model, look: look)
            manifest.entries[index].requires = PixelDiffSampleFeatures.derive(from: try PixelDiffSampleFeatures.json(of: model))
        }
        try manifest.write()
        try await PixelDiffRun.regenerate(manifest: manifest, render: try await PixelDiffMetal.make(manifest: manifest))

        for (name, model, options) in FeatureReferenceTests.cases {
            let raster = try PixelDiff.raster(from: try await FeatureReferenceTests.render(model, options))
            try PixelDiff.write(raster, to: FeatureReferenceTests.directory.appendingPathComponent("\(name).png"))
        }
    }

    /// `./scripts/regenerate-pixel-references.sh --measure-noise`
    @Test(.enabled(if: PixelDiffRegeneration.isNoiseMeasurementRequested))
    func measureNoise() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.measureNoise(manifest: manifest) {
            try await PixelDiffMetal.make(manifest: manifest)
        }
    }
}
