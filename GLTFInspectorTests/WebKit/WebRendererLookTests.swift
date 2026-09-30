import Foundation
import GLTFCore
import Testing
@testable import RendererWebKit

/// `RenderLook` → page values: the one web mapping table (`PageLook`).
struct WebRendererLookTests {
    /// Yaw 0 is the Khronos default view (page rotation 90), whichever surface sends it — the
    /// window, Quick Look and the thumbnail used to disagree by 90°.
    @Test func yawZeroIsTheKhronosDefaultRotation() {
        #expect(PageLook(WebPreviewCanvas.Look()).environmentRotation == 90)
        var look = WebPreviewCanvas.Look()
        look.render.environmentYawDegrees = 30
        #expect(PageLook(look).environmentRotation == 120)
    }

    @Test func renderLookMapsOneToOne() {
        var render = RenderLook.standard
        render.exposureEV = -1.5
        render.environmentIntensity = 0.5
        render.environment = .colorfulStudio
        render.toneMapping = .acesHill
        render.background = RenderLook.Color(red: 1, green: 0.5, blue: 0, alpha: 1)
        let page = PageLook(WebPreviewCanvas.Look(render: render, viewMode: .channel(.normals)))
        #expect(page.exposure == -1.5)
        #expect(page.iblIntensity == 0.5)
        #expect(page.environment == "gltf-inspector:///environments/Colorful_Studio.hdr")
        #expect(page.toneMap == "ACES Filmic Tone Mapping (Hill)")
        #expect(page.background == [1, 0.5, 0, 1])
        #expect(page.debugOutput == "Normal Texture")
        #expect(!page.wireframe)
    }

    /// Quick Look and the thumbnail read the same stored look; only the floor differs by surface.
    @Test func quickLookAndThumbnailShareTheStoredRenderLook() throws {
        let suite = "gltf.web-look.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let thumbnail = WebPreviewCanvas.Look.stored(defaults: defaults, directory: directory)
        let quickLook = WebPreviewCanvas.Look.stored(showsFloor: true, defaults: defaults, directory: directory)
        #expect(thumbnail.render == quickLook.render)
        #expect(PageLook(thumbnail).environmentRotation == PageLook(quickLook).environmentRotation)
    }
}
