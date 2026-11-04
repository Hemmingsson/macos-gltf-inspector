import AppKit
import Foundation
import GLTFCore
import simd
import Testing
@testable import RendererMetal
@testable import RendererWebKit

/// The native host against its oracle, the WebKit page: the same commands must answer with the
/// same camera state, and the same look must draw the same pixels (the pixel-diff comparator and
/// the manifest's tolerance). Each test drives both hosts identically.
@MainActor
@Suite(.serialized)
struct KhronosMetalRendererHostTests {
    static let size = 256

    private func nativeHost(_ mode: WebRendererMode = .still, size: Int = size) async throws -> KhronosMetalRendererHost {
        let host = KhronosMetalRendererHost(mode: mode, size: size)
        try await host.start()
        try await host.apply(WebPreviewCanvas.Look())
        return host
    }

    private func pair(_ model: URL, look: WebPreviewCanvas.Look = .init()) async throws
        -> (page: WebRendererHost, native: KhronosMetalRendererHost) {
        let page = try await WebKitTest.stillHost(size: Self.size)
        let native = try await nativeHost()
        try await page.apply(look)
        try await native.apply(look)
        _ = try await page.load(model: model)
        _ = try await native.load(model: model)
        return (page, native)
    }

    private func expectClose(_ a: Double, _ b: Double, _ label: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let tolerance = max(1e-4, abs(b) * 1e-4)
        #expect(abs(a - b) <= tolerance, "\(label): native \(a) vs page \(b)", sourceLocation: sourceLocation)
    }

    private func expectSameState(_ native: RendererCameraState, _ page: RendererCameraState, _ label: String,
                                 sourceLocation: SourceLocation = #_sourceLocation) {
        expectClose(native.pose.azimuth, page.pose.azimuth, "\(label) azimuth", sourceLocation: sourceLocation)
        expectClose(native.pose.elevation, page.pose.elevation, "\(label) elevation", sourceLocation: sourceLocation)
        expectClose(native.pose.distance, page.pose.distance, "\(label) distance", sourceLocation: sourceLocation)
        expectClose(native.pose.yfov, page.pose.yfov, "\(label) yfov", sourceLocation: sourceLocation)
        expectClose(native.pose.znear, page.pose.znear, "\(label) znear", sourceLocation: sourceLocation)
        expectClose(native.pose.zfar, page.pose.zfar, "\(label) zfar", sourceLocation: sourceLocation)
        for i in 0..<3 {
            expectClose(native.pose.target[i], page.pose.target[i], "\(label) target[\(i)]", sourceLocation: sourceLocation)
            expectClose(native.sceneMin[i], page.sceneMin[i], "\(label) sceneMin[\(i)]", sourceLocation: sourceLocation)
            expectClose(native.sceneMax[i], page.sceneMax[i], "\(label) sceneMax[\(i)]", sourceLocation: sourceLocation)
        }
    }

    private var models: [URL] {
        var urls = [TestFixtures.cube, TestFixtures.offcenter, TestFixtures.boxAnimated, TestFixtures.rigged]
        if TestModels.hasKhronosSamples {
            urls.append(TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb"))
        }
        return urls
    }

    // MARK: - Camera state

    @Test func openingFitMatchesThePage() async throws {
        for model in models {
            for centered in [true, false] {
                let (page, native) = try await pair(model, look: WebPreviewCanvas.Look(isCentered: centered))
                let label = "\(model.lastPathComponent) centered=\(centered)"
                expectSameState(try await native.camera(.get), try await page.camera(.get), "\(label) open")
                expectSameState(try await native.camera(.fit), try await page.camera(.fit), "\(label) fit")
            }
        }
    }

    /// Fit measures at the current angles before restating the front view; centring toggles refit.
    @Test func cameraCommandsMatchThePage() async throws {
        let (page, native) = try await pair(TestFixtures.offcenter)
        let commands: [(String, CameraCommand)] = [
            ("orbit", .orbit(azimuth: 35, elevation: -18)),
            ("orbit+distance", .orbit(azimuth: -90, elevation: 30, distance: 7)),
            ("fit after orbit", .fit),
            ("pose", .pose(CameraPose(azimuth: 12, elevation: 5, distance: 4, target: [0.5, -0.25, 1],
                                      yfov: 0.6, znear: 0.05, zfar: 50))),
            ("get", .get),
        ]
        for (label, command) in commands {
            expectSameState(try await native.camera(command), try await page.camera(command), label)
        }
        _ = try await native.camera(.orbit(azimuth: 40, elevation: 10))
        _ = try await page.camera(.orbit(azimuth: 40, elevation: 10))
        for look in [WebPreviewCanvas.Look(isCentered: false), WebPreviewCanvas.Look(fieldOfView: 30, isCentered: false),
                     WebPreviewCanvas.Look(isOrthographic: true, fieldOfView: 30)] {
            try await native.apply(look)
            try await page.apply(look)
            expectSameState(try await native.camera(.get), try await page.camera(.get), "apply \(look)")
        }
    }

    @Test func sceneSelectionAndVariantMatchThePage() async throws {
        let (page, native) = try await pair(TestFixtures.multiScene)
        _ = try await native.camera(.orbit(azimuth: 20, elevation: 0))
        _ = try await page.camera(.orbit(azimuth: 20, elevation: 0))
        let second = WebPreviewCanvas.Look(sceneIndex: 1)
        try await native.apply(second)
        try await page.apply(second)
        expectSameState(try await native.camera(.get), try await page.camera(.get), "scene 1")
        // A variant change redraws but does not refit, on the page as here.
        let before = try await native.camera(.orbit(azimuth: 50, elevation: 10))
        try await native.apply(WebPreviewCanvas.Look(materialVariantIndex: nil, sceneIndex: 1, showsFloor: true))
        #expect(try await native.camera(.get) == before, "a look change without refit moved the camera")
    }

    @Test func loadInfoMatchesThePage() async throws {
        for model in models {
            let page = try await WebKitTest.stillHost(size: Self.size)
            let native = try await nativeHost()
            let expected = try await page.load(model: model)
            let actual = try await native.load(model: model)
            #expect(actual.triangles == expected.triangles, "\(model.lastPathComponent) triangles")
            #expect(actual.meshes == expected.meshes, "\(model.lastPathComponent) meshes")
            #expect(actual.width == expected.width && actual.height == expected.height)
            #expect(actual.firstFrameMs == 0)
        }
    }

    // MARK: - Pixels

    /// Renders both hosts at the page's own camera and compares with the manifest tolerance.
    private func expectSamePixels(_ model: URL, _ look: WebPreviewCanvas.Look, _ label: String,
                                  sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let (page, native) = try await pair(model, look: look)
        let pose = try await page.camera(.orbit(azimuth: 30, elevation: -20)).pose
        _ = try await native.camera(.pose(pose))
        _ = try await page.camera(.pose(pose))
        let expected = try PixelDiff.raster(from: try await page.renderStill())
        let actual = try PixelDiff.raster(from: try await native.renderStill())
        let tolerance = try PixelDiffManifest.load().tolerance
        let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: tolerance)
        let name = "MetalHost-\(label)".replacingOccurrences(of: " ", with: "_")
        try FileManager.default.createDirectory(at: PixelDiffPaths.outputDirectory, withIntermediateDirectories: true)
        if !verdict.isMatch {
            try PixelDiff.write(actual, to: PixelDiffPaths.outputDirectory.appendingPathComponent("\(name)-actual.png"))
            try PixelDiff.write(expected, to: PixelDiffPaths.outputDirectory.appendingPathComponent("\(name)-expected.png"))
            try PixelDiff.write(PixelDiff.differenceImage(actual: actual, expected: expected),
                                to: PixelDiffPaths.outputDirectory.appendingPathComponent("\(name)-diff.png"))
        }
        print("metal host \(label): \(metrics.summary())")
        #expect(verdict.isMatch, "\(label): \(metrics.summary())", sourceLocation: sourceLocation)
    }

    @Test func overlaysMatchThePage() async throws {
        try await expectSamePixels(TestFixtures.offcenter, WebPreviewCanvas.Look(showsFloor: true), "floor")
        try await expectSamePixels(TestFixtures.offcenter, WebPreviewCanvas.Look(isCentered: false), "origin")
        try await expectSamePixels(TestFixtures.offcenter, WebPreviewCanvas.Look(selectedNodeIndex: 0), "selection")
        try await expectSamePixels(TestFixtures.cube, WebPreviewCanvas.Look(showsFloor: true, isCentered: false,
                                                                           selectedNodeIndex: 0), "all overlays")
    }

    @Test func wireframeAndProjectionMatchThePage() async throws {
        try await expectSamePixels(TestFixtures.cube, WebPreviewCanvas.Look(viewMode: .wireframe), "wireframe")
        try await expectSamePixels(TestFixtures.cube, WebPreviewCanvas.Look(isOrthographic: true), "orthographic")
        // No NORMAL or TEXCOORD: the derivative normal and tangent path.
        try await expectSamePixels(TestFixtures.missingChannels, WebPreviewCanvas.Look(), "basecolor-only shaded")
    }

    @Test func fileCameraMatchesThePage() async throws {
        for node in [1, 2] {
            try await expectSamePixels(TestFixtures.cameras, WebPreviewCanvas.Look(fileCameraNodeIndex: node),
                                       "file camera \(node)")
        }
    }

    /// `basecolor-only` has no UVs, normal map, occlusion, clearcoat or specular: those channels
    /// are the Khronos checkerboard.
    @Test func debugChannelsMatchThePage() async throws {
        var models = [TestFixtures.missingChannels]
        if TestModels.hasKhronosSamples {
            models.append(TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb"))
        }
        for model in models {
            for channel: RenderViewMode.Channel in [.baseColor, .metallic, .roughness, .normals, .tangents,
                                                    .textureCoordinates, .ambientOcclusion, .emissive, .alpha,
                                                    .specular, .clearcoat, .clearcoatRoughness, .clearcoatNormal] {
                try await expectSamePixels(model, WebPreviewCanvas.Look(viewMode: .channel(channel)),
                                           "\(model.deletingPathExtension().lastPathComponent) \(channel)")
            }
        }
    }

    // MARK: - Host semantics

    @Test func stillSizeFollowsTheLastRequest() async throws {
        let native = try await nativeHost(size: 96)
        _ = try await native.load(model: TestFixtures.cube)
        #expect(try await native.renderStill().width == 96)
        #expect(try await native.renderStill(size: 64).width == 64)
        let again = try await native.renderStill()
        #expect(again.width == 64 && again.height == 64, "a still host keeps the size it was last asked for")
        #expect(NSBitmapImageRep(data: try await native.renderStillPNG())?.pixelsWide == 64)
    }

    @Test func rejectedFileFailsTheCallNotTheHost() async throws {
        let native = try await nativeHost()
        _ = try await native.load(model: TestFixtures.cube)
        await #expect(throws: WebRendererError.self) { _ = try await native.load(model: TestFixtures.corrupt) }
        #expect(!native.isBroken)
        // The previous model stays drawable, as the page keeps its last gltf.
        #expect(try await native.renderStill().width == Self.size)
    }

    @Test func callsBeforeStartAreNotReady() async throws {
        let native = KhronosMetalRendererHost(mode: .still, size: 64)
        await #expect(throws: WebRendererError.notReady) { _ = try await native.camera(.get) }
        await #expect(throws: WebRendererError.notReady) { _ = try await native.renderStill() }
    }

    /// Live zoom percent follows every camera change, not only wheel input.
    @Test func liveZoomIsReportedForCommands() async throws {
        let native = try await nativeHost(.live)
        var reported: [Int] = []
        native.onZoom = { reported.append($0) }
        _ = try await native.load(model: TestFixtures.cube)
        #expect(reported.last == 100)
        let pose = try await native.camera(.get).pose
        _ = try await native.camera(.orbit(azimuth: 0, elevation: 0, distance: pose.distance * 2))
        #expect(reported.last == 50)
        _ = try await native.camera(.fit)
        #expect(reported.last == 100)
    }

    /// `UserCamera.zoomBy`, `orbit` and `pan` against values worked from the Khronos source.
    @Test func userCameraInputFollowsKhronos() {
        var camera = MetalUserCamera()
        camera.fit(extents: (SIMD3(-1, -1, -1), SIMD3(1, 1, 1)), centered: true, aspect: 1)
        let base = camera.baseDistance
        camera.zoomBy(10)
        #expect(abs(camera.distance - pow(1 + 0.1, 5) * base) < 1e-9)
        let diagonal = simd_distance(SIMD3<Double>(-1, -1, -1), SIMD3<Double>(1, 1, 1))
        #expect(abs(camera.zfar - (camera.distance + 6 * diagonal)) < 1e-9, "wheel zoom refits the far plane")
        camera.orbit(90, 0)
        #expect(abs(camera.rotAroundY + 0.5) < 1e-12, "90 px orbit is -0.5 rad")
        camera.orbit(0, 10_000)
        #expect(abs(camera.rotAroundX + (Double.pi / 2 - 0.01)) < 1e-12, "elevation clamps at π/2 - 0.01")
        let target = camera.target
        camera.pan(-35, 0)
        #expect(abs(simd_distance(camera.target, target) - 35 * diagonal / 3500 * camera.distance / base) < 1e-9)
    }

    @Test func orthographicLetterboxIsSquare() {
        let wide = khronosViewport(width: 1000, height: 500, aspect: 1)
        #expect(wide.originX == 250 && wide.originY == 0 && wide.width == 500 && wide.height == 500)
        let tall = khronosViewport(width: 300, height: 601, aspect: 1)
        #expect(tall.originX == 0 && tall.width == 300 && tall.height == 300 && tall.originY == 151)
        let full = khronosViewport(width: 640, height: 480, aspect: nil)
        #expect(full.originX == 0 && full.originY == 0 && full.width == 640 && full.height == 480)
    }
}
