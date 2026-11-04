import Foundation

/// An entity a validator issue is about, in the file's own index space. The host turns these into
/// outliner rows; nothing here knows about UI.
public enum GLTFIssueSubject: Sendable, Hashable {
    case node(Int)
    case material(Int)
    case scene(Int)
    case skin(Int)
    case animation(Int)
}

/// Turns a glTF-Validator JSON pointer (`/meshes/0/primitives/1/material`, `/images/2`, …) into
/// the outliner entities the inspector can show it on.
///
/// A pointer into shared data fans out: a mesh is drawn by every node that references it, and an
/// image is used by every material slot that binds a texture over it. An issue that points at
/// nothing the outliner shows (an accessor, a buffer view) resolves to no subjects and stays in
/// the sidebar's overall list only.
public enum GLTFIssueResolver {
    public static func subjects(
        forPointer pointer: String?,
        in document: GLTFDocument
    ) -> [GLTFIssueSubject] {
        guard let pointer else { return [] }
        let parts = pointer.split(separator: "/").map(String.init)
        guard parts.count >= 2, let index = Int(parts[1]) else { return [] }

        var result: [GLTFIssueSubject] = []
        func add(_ subject: GLTFIssueSubject) {
            if !result.contains(subject) { result.append(subject) }
        }

        switch parts[0] {
        case "nodes":
            if document.nodes.contains(where: { $0.index == index }) { add(.node(index)) }
        case "scenes":
            if document.scenes.indices.contains(index) { add(.scene(index)) }
        case "materials":
            if document.materials.indices.contains(index) { add(.material(index)) }
        case "skins":
            if document.skins.indices.contains(index) { add(.skin(index)) }
        case "animations":
            if document.animations.indices.contains(index) { add(.animation(index)) }
        case "cameras":
            for node in document.nodes where node.cameraIndex == index { add(.node(node.index)) }
        case "meshes":
            for node in document.nodes where node.meshIndex == index { add(.node(node.index)) }
            if let material = primitiveMaterial(parts, mesh: index, document: document) {
                add(.material(material))
            }
        case "textures":
            for material in materialIndices(using: document, matching: { $0.textureIndex == index }) {
                add(.material(material))
            }
        case "images":
            for material in materialIndices(using: document, matching: { $0.imageIndex == index }) {
                add(.material(material))
            }
        default:
            break
        }
        return result
    }

    /// `/meshes/M/primitives/P/…` → the material primitive P of mesh M uses.
    private static func primitiveMaterial(
        _ parts: [String],
        mesh: Int,
        document: GLTFDocument
    ) -> Int? {
        guard parts.count >= 4, parts[2] == "primitives", let primitive = Int(parts[3]),
              document.meshPrimitiveMaterials.indices.contains(mesh),
              document.meshPrimitiveMaterials[mesh].indices.contains(primitive)
        else { return nil }
        return document.meshPrimitiveMaterials[mesh][primitive]
    }

    private static func materialIndices(
        using document: GLTFDocument,
        matching: (GLTFDocument.TextureSlot) -> Bool
    ) -> [Int] {
        document.materials.indices.filter { document.materials[$0].textures.contains(where: matching) }
    }
}
