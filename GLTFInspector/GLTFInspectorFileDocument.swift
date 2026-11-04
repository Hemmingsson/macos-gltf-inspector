import SwiftUI
import UniformTypeIdentifiers

/// Stub viewer document. `DocumentWindow` loads from `FileDocumentConfiguration.fileURL`.
struct GLTFInspectorFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            UTType(importedAs: "org.khronos.glb"),
            UTType(importedAs: "org.khronos.gltf"),
        ]
    }

    static var writableContentTypes: [UTType] { [] }

    init(configuration: ReadConfiguration) throws {
        // Intentionally ignore FileWrapper bytes — the page loads from the file URL, so sidecar
        // buffers and textures resolve against its folder.
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
