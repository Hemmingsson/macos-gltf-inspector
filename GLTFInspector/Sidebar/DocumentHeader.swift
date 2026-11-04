import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// The file-name block at the top of the sidebar — `DSDocumentCard` plus an optional
/// material-variant `DSMenuPicker`. Shows the name without its extension, and the file format
/// under it.
///
/// The window has no title band (DESIGN.md: the file name lives in the sidebar), so if this
/// block is missing there is nothing anywhere on screen that says which file you are looking at.
struct DocumentHeader: View {
    var fileName: String
    var variantNames: [String] = []
    @Binding var selectedVariantIndex: Int?

    var body: some View {
        let title = DocumentIdentity.title(fileName)
        let subtitle = DocumentIdentity.kind(fileName)
        Group {
            if variantNames.isEmpty {
                DSDocumentCard(title, subtitle: subtitle)
            } else {
                DSDocumentCard(title, subtitle: subtitle) {
                    DSMenuPicker(
                        "Material variant",
                        selection: $selectedVariantIndex,
                        options: [nil] + variantNames.indices.map { Optional($0) },
                        labelVisibility: .hidden
                    ) { $0.map { variantNames[$0] } ?? "Default" }
                    .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.paneInset)
        .padding(.vertical, DS.Spacing.m)
    }
}

/// How the document names itself on the sidebar card: the file name without its extension, and
/// the file kind as Finder writes it ("GL Transmission Format - Binary").
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
