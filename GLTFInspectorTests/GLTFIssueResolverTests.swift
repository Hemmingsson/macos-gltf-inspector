import Foundation
@testable import GLTFCore
import Testing

/// Validator JSON pointers → the outliner entities an issue is shown on.
struct GLTFIssueResolverTests {
    /// Two nodes share mesh 0. Its primitive 0 uses material 1, primitive 1 has no material.
    /// Material 1 binds texture 0, which is image 2.
    private let document: GLTFSessionDocument = GLTFDocumentJSON.makeDocument(json: [
        "scenes": [["nodes": [0, 1, 2]]],
        "nodes": [["mesh": 0], ["mesh": 0], ["camera": 0]],
        "cameras": [["type": "perspective", "perspective": ["yfov": 1, "znear": 0.1]]],
        "meshes": [["primitives": [
            ["attributes": ["POSITION": 0], "material": 1],
            ["attributes": ["POSITION": 0]],
        ]]],
        "materials": [
            [:],
            ["pbrMetallicRoughness": ["baseColorTexture": ["index": 0]]],
        ],
        "textures": [["source": 2]],
        "images": [["uri": "a.png"], ["uri": "b.png"], ["uri": "c.png"]],
    ])

    private func subjects(_ pointer: String?) -> [GLTFIssueSubject] {
        GLTFIssueResolver.subjects(forPointer: pointer, in: document)
    }

    @Test func nodeAndMaterialPointersResolveToThemselves() {
        #expect(subjects("/nodes/1") == [.node(1)])
        #expect(subjects("/materials/0") == [.material(0)])
        #expect(subjects("/scenes/0") == [.scene(0)])
    }

    @Test func meshPointerFansOutToEveryNodeUsingTheMesh() {
        #expect(subjects("/meshes/0") == [.node(0), .node(1)])
    }

    @Test func primitivePointerAlsoReachesThatPrimitivesMaterial() {
        #expect(subjects("/meshes/0/primitives/0") == [.node(0), .node(1), .material(1)])
        #expect(subjects("/meshes/0/primitives/0/attributes") == [.node(0), .node(1), .material(1)])
        // The exact pointer the validator gives MESH_PRIMITIVE_GENERATED_TANGENT_SPACE.
        #expect(subjects("/meshes/0/primitives/0/material") == [.node(0), .node(1), .material(1)])
        // Primitive 1 has no material, so only the nodes.
        #expect(subjects("/meshes/0/primitives/1") == [.node(0), .node(1)])
    }

    @Test func imageAndTexturePointersReachTheMaterialsThatBindThem() {
        #expect(subjects("/images/2") == [.material(1)])
        #expect(subjects("/textures/0") == [.material(1)])
        // An image no material binds has nowhere to show.
        #expect(subjects("/images/0").isEmpty)
    }

    @Test func cameraPointerResolvesToItsNode() {
        #expect(subjects("/cameras/0") == [.node(2)])
    }

    @Test func unshownOrMalformedPointersResolveToNothing() {
        #expect(subjects(nil).isEmpty)
        #expect(subjects("").isEmpty)
        #expect(subjects("/").isEmpty)
        #expect(subjects("/accessors/3").isEmpty)
        #expect(subjects("/materials/9").isEmpty)
        #expect(subjects("/materials/x").isEmpty)
    }
}
