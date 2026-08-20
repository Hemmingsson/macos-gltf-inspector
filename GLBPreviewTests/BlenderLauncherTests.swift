import Foundation
import Testing
@testable import GLBPreview

struct BlenderLauncherTests {
    @Test func importScriptDefersImportAndDismissesSplash() {
        let url = URL(fileURLWithPath: "/tmp/model.glb")
        let script = BlenderLauncher.importScript(for: url)
        #expect(script.contains("show_splash = False"))
        #expect(script.contains("bpy.app.timers.register"))
        #expect(script.contains("import_scene.gltf"))
        #expect(!script.contains("read_homefile"))
    }

    @Test func importScriptEmbedsJSONEncodedAbsolutePath() {
        let url = URL(fileURLWithPath: "/Users/test/Models/cube.glb")
        let script = BlenderLauncher.importScript(for: url)
        #expect(script.contains(#"_filepath = "/Users/test/Models/cube.glb""#))
    }

    @Test func importScriptEncodesSpacesAndQuotes() {
        let url = URL(fileURLWithPath: "/tmp/My \"Quoted\" Model.glb")
        let script = BlenderLauncher.importScript(for: url)
        #expect(script.contains(#"_filepath = "/tmp/My \"Quoted\" Model.glb""#))
    }
}
