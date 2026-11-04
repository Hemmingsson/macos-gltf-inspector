import Foundation
import UniformTypeIdentifiers

/// How the document names itself in the sidebar card and the document inspector: the file name
/// without its extension, and the file kind as Finder writes it ("GL Transmission Format - Binary").
enum DocumentIdentity {
    static func title(_ fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? fileName : stem
    }

    /// The system's description of the extension's type, so it matches Finder's Kind column.
    /// Falls back to a plain name when no app on the system declares the type.
    static func kind(_ fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        if let description = UTType(filenameExtension: ext)?.localizedDescription,
           !description.isEmpty {
            return description
        }
        switch ext {
        case "glb": return "glTF Binary"
        case "gltf": return "glTF"
        default: return ext.uppercased()
        }
    }
}
