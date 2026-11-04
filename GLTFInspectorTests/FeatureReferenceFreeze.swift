import Foundation
import GLTFCore
import Testing
@testable import RendererMetal
@testable import RendererWebKit

/// One-off: renders every feature case on the Khronos page, checks the Metal host draws the same,
/// and writes the page's PNG to `TestModels/References/Features/`. Run once before the page is
/// deleted.
@MainActor
@Suite(.serialized)
struct FeatureReferenceFreeze {
    static let size = 256
    static var boomBox: URL { TestModels.khronosDirectory.appendingPathComponent("BoomBox/BoomBox.glb") }

    static var cases: [(String, URL, WebPreviewCanvas.Look)] {
        var cases: [(String, URL, WebPreviewCanvas.Look)] = [
            ("floor", TestFixtures.offcenter, .init(showsFloor: true)),
            ("origin", TestFixtures.offcenter, .init(isCentered: false)),
            ("selection", TestFixtures.offcenter, .init(selectedNodeIndex: 0)),
            ("all-overlays", TestFixtures.cube, .init(showsFloor: true, isCentered: false, selectedNodeIndex: 0)),
            ("wireframe", TestFixtures.cube, .init(viewMode: .wireframe)),
            ("orthographic", TestFixtures.cube, .init(isOrthographic: true)),
            ("narrow-fov", TestFixtures.cube, .init(fieldOfView: 25)),
            ("basecolor-only", TestFixtures.missingChannels, .init()),
            ("file-camera-1", TestFixtures.cameras, .init(fileCameraNodeIndex: 1)),
            ("file-camera-2", TestFixtures.cameras, .init(fileCameraNodeIndex: 2)),
            ("second-scene", TestFixtures.multiScene, .init(sceneIndex: 1)),
            ("punctual-lights", TestFixtures.lights, .init()),
        ]
        let channels: [RenderViewMode.Channel] = [
            .baseColor, .metallic, .roughness, .normals, .tangents, .textureCoordinates, .ambientOcclusion,
            .emissive, .alpha, .specular, .clearcoat, .clearcoatRoughness, .clearcoatNormal,
        ]
        for channel in channels {
            cases.append(("basecolor-only-\(channel)", TestFixtures.missingChannels, .init(viewMode: .channel(channel))))
            cases.append(("BoomBox-\(channel)", boomBox, .init(viewMode: .channel(channel))))
        }
        func look(_ edit: (inout RenderLook) -> Void) -> WebPreviewCanvas.Look {
            var render = RenderLook.standard
            edit(&render)
            return .init(render: render)
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

    @Test func freeze() async throws {
        let directory = PixelDiffPaths.referencesDirectory.appendingPathComponent("Features")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tolerance = try PixelDiffManifest.load().tolerance
        var mismatches: [String] = []
        for (name, model, look) in Self.cases {
            let page = try await WebKitTest.stillHost(size: Self.size)
            let native = KhronosMetalRendererHost(mode: .still, size: Self.size)
            try await native.start()
            for host in [page, native] as [any CanvasRendererHost] {
                try await host.apply(look)
                _ = try await host.load(model: model)
                _ = try await host.camera(.orbit(azimuth: 30, elevation: -20))
            }
            let expected = try PixelDiff.raster(from: try await page.renderStill())
            let actual = try PixelDiff.raster(from: try await native.renderStill())
            let (metrics, verdict) = try PixelDiff.compare(actual, to: expected, tolerance: tolerance)
            print("feature \(name): \(metrics.summary())")
            if !verdict.isMatch { mismatches.append(name) }
            try PixelDiff.write(expected, to: directory.appendingPathComponent("\(name).png"))
        }
        #expect(mismatches.isEmpty, "native differs from the page: \(mismatches)")
    }
}
