import Foundation
@testable import GLTFCore
@testable import GLTFInspector
import PreviewUI
import Testing

struct EngineCoreMappingTests {
    @Test func viewModesRoundTrip() {
        let modes: [ViewMode] = [.shaded, .wireframe] + DebugChannel.allCases.map { .channel($0) }
        for mode in modes {
            #expect(ViewMode(RenderViewMode(mode)) == mode)
        }
        #expect(RenderViewMode.Channel.allCases.count == DebugChannel.allCases.count)
    }

    @Test func cameraPresetsRoundTrip() {
        for preset in PreviewUI.CameraPreset.allCases {
            let core = GLTFCore.CameraPreset(preset)
            #expect(core.rawValue == preset.rawValue)
        }
        #expect(GLTFCore.CameraPreset.allCases.count == PreviewUI.CameraPreset.allCases.count)
    }

    @Test func toneMappingKeepsKhronosNames() {
        for toneMapping in ToneMapping.allCases {
            #expect(RenderLook.ToneMapping(toneMapping).rawValue == toneMapping.khronosName)
        }
    }

    @Test func environmentsKeepCatalogIDs() {
        for environment in StudioEnvironment.allCases {
            #expect(KhronosEnvironments(environment).rawValue == environment.rawValue)
        }
    }

    @Test func standardLightingIsTheStandardLook() {
        #expect(RenderLook(LightingSettings.standard, backdrop: .window) == .standard)
    }

    @Test func lookIsCodable() throws {
        var look = RenderLook.standard
        look.background = RenderLook.Color(.dark)
        look.toneMapping = .acesHill
        let data = try JSONEncoder().encode(look)
        #expect(try JSONDecoder().decode(RenderLook.self, from: data) == look)
    }
}
