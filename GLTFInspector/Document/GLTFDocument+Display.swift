import GLTFCore
import simd
import SwiftUI

// How the outliner and inspector name and format what the file says: fallback names for unnamed
// entries, degrees for angles, Euler rotation for quaternions. The document itself stays as
// authored.

extension GLTFDocument {
    /// The outliner row for a node, typed by what it carries.
    func id(ofNode index: Int) -> NodeID? {
        nodes.indices.contains(index) ? NodeID(kind: NodeKind(nodes[index].kind), index: index) : nil
    }

    /// How many nodes reference each mesh index. Pass into `assetImage(for:meshRefs:)` so shared
    /// (instanced) meshes can use the component glyph without rescanning per row.
    func meshReferenceCounts() -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for node in nodes {
            guard let meshIndex = node.meshIndex else { continue }
            counts[meshIndex, default: 0] += 1
        }
        return counts
    }

    /// SF Symbol for an outliner / inspector glyph. Light rows follow `KHR_lights_punctual` type;
    /// the file's default scene uses `house`.
    func systemImage(for id: NodeID) -> String {
        if id.kind == .light,
           nodes.indices.contains(id.index),
           let lightIndex = nodes[id.index].lightIndex,
           lights.indices.contains(lightIndex) {
            return lights[lightIndex].systemImage
        }
        if id.kind == .scene, id.index == defaultSceneIndex {
            return "house"
        }
        return id.kind.systemImage
    }

    /// Catalog image for an outliner / inspector glyph (Blender lights, Spline shared mesh, …).
    /// `nil` → material swatch or SF Symbol from `systemImage(for:)`.
    func assetImage(for id: NodeID, meshRefs: [Int: Int]? = nil) -> String? {
        if id.kind == .light,
           nodes.indices.contains(id.index),
           let lightIndex = nodes[id.index].lightIndex,
           lights.indices.contains(lightIndex) {
            return BlenderIcons.lightType(lights[lightIndex].type)
        }
        // Material rows draw a base-color swatch instead of catalog art.
        if id.kind == .material { return nil }
        if id.kind == .mesh,
           nodes.indices.contains(id.index),
           let meshIndex = nodes[id.index].meshIndex {
            let refs = meshRefs ?? meshReferenceCounts()
            if refs[meshIndex, default: 0] > 1 {
                return SplineIcons.sharedMesh
            }
        }
        return SplineIcons.nodeKind(id.kind)
    }

    /// Material ball tint from `baseColorFactor` (always authored-or-default by the JSON reader).
    func swatchColor(for id: NodeID) -> Color? {
        guard id.kind == .material,
              materials.indices.contains(id.index),
              let factor = materials[id.index].baseColorFactor else { return nil }
        return Color(
            .sRGB,
            red: Double(factor.x),
            green: Double(factor.y),
            blue: Double(factor.z),
            opacity: Double(factor.w)
        )
    }

    /// VoiceOver / inspector subtype title for a light row; other kinds use `NodeKind.displayTitle`.
    func displayKindTitle(of id: NodeID) -> String {
        if id.kind == .light,
           nodes.indices.contains(id.index),
           let lightIndex = nodes[id.index].lightIndex,
           lights.indices.contains(lightIndex) {
            return lights[lightIndex].displayTypeTitle
        }
        return id.kind.displayTitle
    }

    /// The name shown for any outliner row.
    func displayName(of id: NodeID) -> String {
        let index = id.index
        func name<T>(_ list: [T], _ authored: (T) -> String, _ fallback: String) -> String {
            list.indices.contains(index) ? authored(list[index]).displayName(or: fallback) : fallback
        }
        return switch id.kind {
        case .mesh, .camera, .light, .empty: name(nodes, \.name, "Node \(index)")
        case .skin: name(skins, \.name, "Skin \(index)")
        case .scene: name(scenes, \.name, "Scene \(index)")
        case .material: name(materials, \.name, "Material \(index)")
        case .animation: name(animations, \.name, "Clip \(index + 1)")
        case .morph: name(morphs, \.meshName, "Mesh \(index)")
        }
    }

    /// Names of the nodes whose mesh uses material `index`.
    func meshNames(usingMaterial index: Int) -> [String] {
        nodes.filter { $0.materialIndices.contains(index) }.map { $0.name.displayName(or: "Node \($0.index)") }
    }
}

extension NodeKind {
    init(_ kind: GLTFDocument.Node.Kind) {
        switch kind {
        case .empty: self = .empty
        case .mesh: self = .mesh
        case .camera: self = .camera
        case .light: self = .light
        // A skin needs a mesh; a node with only a skin draws nothing and is shown as a group.
        case .skin: self = .empty
        }
    }
}

extension String {
    /// Trimmed, or `fallback` when nothing is left.
    func displayName(or fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

extension GLTFDocument.Node {
    /// Intrinsic XYZ Euler degrees of the authored rotation (how glTF TRS is usually authored).
    var rotationDegrees: SIMD3<Double> {
        let x = Double(rotation.imag.x), y = Double(rotation.imag.y), z = Double(rotation.imag.z)
        let w = Double(rotation.real)
        let roll = atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
        let sinPitch = 2 * (w * y - z * x)
        let pitch = abs(sinPitch) >= 1 ? copysign(.pi / 2, sinPitch) : asin(sinPitch)
        let yaw = atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        return SIMD3(roll, pitch, yaw) * 180 / .pi
    }
}

extension GLTFDocument.TextureSlot.Kind {
    /// Full name, for map rows and accessibility.
    var title: String {
        switch self {
        case .baseColor: "Base Color"
        case .normal: "Normal"
        case .metallicRoughness: "Metallic Roughness"
        case .occlusion: "Ambient Occlusion"
        case .emissive: "Emissive"
        case .clearcoat: "Clearcoat"
        case .clearcoatRoughness: "Clearcoat Roughness"
        case .clearcoatNormal: "Clearcoat Normal"
        case .specular: "Specular"
        }
    }

    /// Chip label on a mesh's material.
    var shortTitle: String {
        switch self {
        case .baseColor: "Base"
        case .normal: "Normal"
        case .metallicRoughness: "Rough"
        case .occlusion: "AO"
        case .emissive: "Emissive"
        case .clearcoat: "Coat"
        case .clearcoatRoughness: "Coat R"
        case .clearcoatNormal: "Coat N"
        case .specular: "Spec"
        }
    }
}

extension GLTFDocument.Material {
    var workflowTitle: String {
        switch workflow {
        case .metallicRoughness: "Metallic Roughness"
        case .specularGlossiness: "Specular Glossiness"
        case .unlit: "Unlit"
        }
    }

    var alphaTitle: String {
        switch alphaMode {
        case .opaque: "Opaque"
        case .blend: "Blend"
        case .mask: alphaCutoff.map { String(format: "Mask (cutoff %.2g)", $0) } ?? "Mask"
        }
    }

    func hasMap(_ kind: GLTFDocument.TextureSlot.Kind) -> Bool {
        textures.contains { $0.kind == kind }
    }

    // Factors are shown only when they differ from the glTF default and no map already covers
    // the channel, so a calm material stays calm.

    var visibleBaseColorFactor: SIMD4<Float>? {
        guard !hasMap(.baseColor), let factor = baseColorFactor, !factor.isClose(to: .one) else { return nil }
        return factor
    }

    var visibleMetallicFactor: Float? {
        hasMap(.metallicRoughness) ? nil : metallicFactor.flatMap { $0.isClose(to: 1) ? nil : $0 }
    }

    var visibleRoughnessFactor: Float? {
        hasMap(.metallicRoughness) ? nil : roughnessFactor.flatMap { $0.isClose(to: 1) ? nil : $0 }
    }

    var visibleEmissiveFactor: SIMD3<Float>? {
        guard !hasMap(.emissive), let factor = emissiveFactor, !SIMD4(factor, 1).isClose(to: SIMD4(0, 0, 0, 1)) else { return nil }
        return factor
    }

    var visibleEmissiveStrength: Float? {
        emissiveStrength.flatMap { $0.isClose(to: 1) ? nil : $0 }
    }

    /// Scale and strength only mean something on top of their map.
    var visibleNormalScale: Float? {
        hasMap(.normal) ? normalScale.flatMap { $0.isClose(to: 1) ? nil : $0 } : nil
    }

    var visibleOcclusionStrength: Float? {
        hasMap(.occlusion) ? occlusionStrength.flatMap { $0.isClose(to: 1) ? nil : $0 } : nil
    }
}

private extension Float {
    func isClose(to other: Float) -> Bool { abs(self - other) <= 0.004 }
}

private extension SIMD4<Float> {
    /// RGB within 1/255 of `other`; alpha is not shown.
    func isClose(to other: Self) -> Bool {
        abs(x - other.x) <= 0.004 && abs(y - other.y) <= 0.004 && abs(z - other.z) <= 0.004
    }
}

extension ModelBounds {
    /// Where the authored glTF origin sits relative to the box centre the canvas frames.
    var authoredOrigin: SIMD3<Float> { -center }
}

extension GLTFDocument.Light {
    /// SF Symbol fallback when Blender light glyphs are unavailable.
    var systemImage: String {
        switch type {
        case "directional": "lamp.desk"
        case "point": "ring.light"
        case "spot": "light.overhead.right"
        default: "lamp.desk"
        }
    }

    /// Subtype label for the inspector and VoiceOver.
    var displayTypeTitle: String {
        switch type {
        case "directional": "Directional Light"
        case "point": "Point Light"
        case "spot": "Spot Light"
        default: "Light"
        }
    }
}
