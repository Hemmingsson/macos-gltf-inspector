import Foundation
@testable import GLTFCore
import RealityKit
@testable import RendererRealityKit
import Testing

// Load-and-inspect helpers over converted RealityKit entities. GLB byte builders are
// renderer-neutral: `TestGLBFixtures.swift` at the test root.

@MainActor
func pbrMaterials(in entity: Entity) -> [PhysicallyBasedMaterial] {
    var out: [PhysicallyBasedMaterial] = []
    if let model = entity.components[ModelComponent.self] {
        for material in model.materials {
            if let pbr = material as? PhysicallyBasedMaterial {
                out.append(pbr)
            }
        }
    }
    for child in entity.children {
        out.append(contentsOf: pbrMaterials(in: child))
    }
    return out
}

func hasVisibleEmissive(_ material: PhysicallyBasedMaterial) -> Bool {
    if material.emissiveColor.texture != nil { return true }
    guard let components = material.emissiveColor.color.cgColor.components, components.count >= 3 else {
        return false
    }
    return max(components[0], max(components[1], components[2])) > 0.05
}

@MainActor
func loadFirstPBR(_ glb: Data) async throws -> PhysicallyBasedMaterial {
    let all = try await loadAllPBR(glb)
    try #require(!all.isEmpty)
    return all[0]
}

@MainActor
func loadModel(_ glb: Data, includeAnimations: Bool = false) async throws -> EntityLoader.LoadedModel {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("load-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("m.glb")
    try glb.write(to: url)
    return try await EntityLoader.load(from: url, includeAnimations: includeAnimations)
}

@MainActor
func firstComponent<T: Component>(_ type: T.Type, in entity: Entity) -> T? {
    if let found = entity.components[type] { return found }
    for child in entity.children {
        if let found = firstComponent(type, in: child) { return found }
    }
    return nil
}

@MainActor
func entity(nodeIndex: Int, in root: Entity) -> Entity? {
    GLTFNodeLookup.entity(nodeIndex: nodeIndex, in: root)
}

@MainActor
func namedEntity(_ name: String, in entity: Entity) -> Entity? {
    if entity.name == name { return entity }
    for child in entity.children {
        if let found = namedEntity(name, in: child) { return found }
    }
    return nil
}

@MainActor
func stampedNodeIndices(in entity: Entity) -> Set<Int> {
    var found = Set<Int>()
    func walk(_ node: Entity) {
        if let id = node.components[GLTFNodeIDComponent.self]?.nodeIndex {
            found.insert(id)
        }
        node.children.forEach(walk)
    }
    walk(entity)
    return found
}

@MainActor
func loadAllPBR(_ glb: Data) async throws -> [PhysicallyBasedMaterial] {
    pbrMaterials(in: try await loadModel(glb).entity)
}

@MainActor
func firstMeshUVs(in entity: Entity) -> [SIMD2<Float>]? {
    if let model = entity.components[ModelComponent.self] {
        for meshModel in model.mesh.contents.models {
            for part in meshModel.parts {
                if let uvs = part[MeshBuffers.textureCoordinates] {
                    let array = Array(uvs)
                    // LowLevelMesh-backed resources can expose an empty MeshBuffers view.
                    if !array.isEmpty { return array }
                }
            }
        }
    }
    for child in entity.children {
        if let uvs = firstMeshUVs(in: child) {
            return uvs
        }
    }
    return nil
}
