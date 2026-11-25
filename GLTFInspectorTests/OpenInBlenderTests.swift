import Foundation
@testable import GLTFInspector
import Testing

/// Blender's `File ▸ Open` rejects glTF ("File format is not supported"), so the Open-in menu
/// drives the importer instead. These guard the expression it hands Blender.
struct OpenInBlenderTests {
    @Test
    func scriptImportsFromTheEnvironmentIntoAnEmptyScene() {
        let script = OpenInButton.blenderImportScript
        #expect(script.contains("bpy.ops.wm.read_homefile(use_empty=True)"))
        #expect(script.contains("bpy.ops.import_scene.gltf("))
        #expect(script.contains("os.environ[\"\(OpenInButton.blenderPathVariable)\"]"))
    }

    /// The path never appears in the expression, so quotes, spaces and newlines in a file name
    /// cannot break or inject into it.
    @Test
    func scriptCarriesNoFilePath() {
        #expect(!OpenInButton.blenderImportScript.contains("filepath=\"/"))
        #expect(!OpenInButton.blenderImportScript.contains("'"))
    }
}
