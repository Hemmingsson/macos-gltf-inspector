import SwiftUI
import UniformTypeIdentifiers

/// Stub viewer document. Actual mesh load uses `FileDocumentConfiguration.fileURL` via `EntityLoader`.
struct GLBPreviewFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            UTType(importedAs: "org.khronos.glb"),
            UTType(importedAs: "org.khronos.gltf"),
        ]
    }

    static var writableContentTypes: [UTType] { [] }

    init() {}

    init(configuration: ReadConfiguration) throws {
        // Intentionally ignore FileWrapper bytes — GLTFKit2 needs a filesystem URL + parent dir.
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}
