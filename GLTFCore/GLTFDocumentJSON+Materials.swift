import Foundation

/// Materials, their texture bindings and the inspector's texture previews.
extension GLTFDocumentJSON {
    private static let specGlossExtension = "KHR_materials_pbrSpecularGlossiness"

    static func makeMaterial(_ material: [String: Any]) -> GLTFSessionDocument.Material {
        let extensions = material["extensions"] as? [String: Any] ?? [:]
        let specGloss = extensions[specGlossExtension] as? [String: Any]
        let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]

        let workflow: GLTFSessionDocument.Material.Workflow
        if extensions["KHR_materials_unlit"] != nil {
            workflow = .unlit
        } else if specGloss != nil {
            workflow = .specularGlossiness
        } else {
            workflow = .metallicRoughness
        }

        let alphaMode: GLTFSessionDocument.Material.AlphaMode
        switch (material["alphaMode"] as? String)?.uppercased() {
        case "MASK": alphaMode = .mask
        case "BLEND": alphaMode = .blend
        default: alphaMode = .opaque
        }

        // Factors are reported at their glTF-effective value: an omitted key still shades the
        // model. The inspector hides the calm defaults, so this never adds noise.
        let baseColor = specGloss.flatMap { GLTFJSON.float4($0["diffuseFactor"]) }
            ?? GLTFJSON.float4(pbr["baseColorFactor"])
            ?? SIMD4<Float>(1, 1, 1, 1)
        let isSpecGloss = workflow == .specularGlossiness

        return GLTFSessionDocument.Material(
            name: material["name"] as? String ?? "",
            maps: MaterialMapPresence.from(json: material),
            workflow: workflow,
            alphaMode: alphaMode,
            isDoubleSided: material["doubleSided"] as? Bool ?? false,
            metallicFactor: isSpecGloss ? nil : (GLTFJSON.float(pbr["metallicFactor"]) ?? 1),
            roughnessFactor: isSpecGloss ? nil : (GLTFJSON.float(pbr["roughnessFactor"]) ?? 1),
            alphaCutoff: alphaMode == .mask ? (GLTFJSON.float(material["alphaCutoff"]) ?? 0.5) : nil,
            baseColorFactor: baseColor,
            emissiveFactor: GLTFJSON.float3(material["emissiveFactor"]),
            // Scale/strength only mean something on top of their map.
            normalScale: (material["normalTexture"] as? [String: Any]).map {
                GLTFJSON.float($0["scale"]) ?? 1
            },
            occlusionStrength: (material["occlusionTexture"] as? [String: Any]).map {
                GLTFJSON.float($0["strength"]) ?? 1
            },
            textures: textureSlots(material)
        )
    }

    /// Authored map bindings in inspector order.
    private static func textureSlots(_ material: [String: Any]) -> [GLTFSessionDocument.TextureSlot] {
        textureRefs(material).map { ref in
            GLTFSessionDocument.TextureSlot(
                kind: ref.kind,
                texCoord: GLTFJSON.int(ref.params["texCoord"]) ?? 0
            )
        }
    }

    /// Every authored texture binding on a material, in the order the inspector lists them.
    /// The one binding table: `MaterialMapPresence.from(json:)` reads it too.
    static func textureRefs(
        _ material: [String: Any]
    ) -> [(kind: GLTFSessionDocument.TextureSlot.Kind, params: [String: Any])] {
        let extensions = material["extensions"] as? [String: Any] ?? [:]
        let specGloss = extensions[specGlossExtension] as? [String: Any] ?? [:]
        let pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]
        let specular = extensions["KHR_materials_specular"] as? [String: Any] ?? [:]
        let clearcoat = extensions["KHR_materials_clearcoat"] as? [String: Any] ?? [:]

        var refs: [(kind: GLTFSessionDocument.TextureSlot.Kind, params: [String: Any])] = []
        func append(_ kind: GLTFSessionDocument.TextureSlot.Kind, _ candidates: [Any?]) {
            for candidate in candidates {
                if let params = candidate as? [String: Any] {
                    refs.append((kind, params))
                    return
                }
            }
        }
        append(.baseColor, [pbr["baseColorTexture"], specGloss["diffuseTexture"]])
        append(.metallicRoughness, [pbr["metallicRoughnessTexture"]])
        append(.normal, [material["normalTexture"]])
        append(.occlusion, [material["occlusionTexture"]])
        append(.emissive, [material["emissiveTexture"]])
        append(.specular, [
            specular["specularTexture"],
            specular["specularColorTexture"],
            specGloss["specularGlossinessTexture"],
        ])
        append(.clearcoat, [clearcoat["clearcoatTexture"]])
        append(.clearcoatRoughness, [clearcoat["clearcoatRoughnessTexture"]])
        append(.clearcoatNormal, [clearcoat["clearcoatNormalTexture"]])
        return refs
    }

    /// Pixel size + PNG thumb per bound map, decoded straight from the file's images.
    static func stampTexturePreviews(
        _ document: inout GLTFSessionDocument,
        json: [String: Any],
        materialsJSON: [[String: Any]],
        binary: GLTFBinaryStore
    ) {
        let textures = json["textures"] as? [[String: Any]] ?? []
        let images = json["images"] as? [[String: Any]] ?? []
        guard !textures.isEmpty, !images.isEmpty else { return }

        var previews: [Int: (size: (width: Int, height: Int)?, thumb: Data?)] = [:]
        func preview(forImage index: Int) -> (size: (width: Int, height: Int)?, thumb: Data?) {
            if let cached = previews[index] { return cached }
            var built: (size: (width: Int, height: Int)?, thumb: Data?) = (nil, nil)
            if images.indices.contains(index), let bytes = binary.imageBytes(images[index]) {
                built = (GLTFImageDecode.pixelSize(of: bytes), GLTFImageDecode.thumbnailPNG(from: bytes, maxEdge: 96))
            }
            previews[index] = built
            return built
        }

        for materialIndex in document.materials.indices {
            guard materialsJSON.indices.contains(materialIndex) else { continue }
            let bindings = textureBindings(materialsJSON[materialIndex])
            var slots = document.materials[materialIndex].textures
            for slotIndex in slots.indices {
                guard let textureIndex = bindings[slots[slotIndex].kind],
                      textures.indices.contains(textureIndex),
                      let imageIndex = imageIndex(for: textures[textureIndex])
                else { continue }
                let built = preview(forImage: imageIndex)
                slots[slotIndex].width = built.size?.width
                slots[slotIndex].height = built.size?.height
                slots[slotIndex].thumbnailPNG = built.thumb
            }
            document.materials[materialIndex].textures = slots
        }
    }

    /// `source`, or the decoded image behind a supported texture extension.
    private static func imageIndex(for texture: [String: Any]) -> Int? {
        if let source = GLTFJSON.int(texture["source"]) { return source }
        let extensions = texture["extensions"] as? [String: Any] ?? [:]
        for name in ["EXT_texture_webp", "KHR_texture_basisu"] {
            if let entry = extensions[name] as? [String: Any],
               let source = GLTFJSON.int(entry["source"]) {
                return source
            }
        }
        return nil
    }

    private static func textureBindings(
        _ material: [String: Any]
    ) -> [GLTFSessionDocument.TextureSlot.Kind: Int] {
        var bindings: [GLTFSessionDocument.TextureSlot.Kind: Int] = [:]
        for ref in textureRefs(material) {
            guard let index = GLTFJSON.int(ref.params["index"]) else { continue }
            bindings[ref.kind] = index
        }
        return bindings
    }
}
