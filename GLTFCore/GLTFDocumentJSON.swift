import Foundation
import simd

/// Builds `GLTFSessionDocument` from the glTF JSON itself — no renderer in the call path.
///
/// The sidebar is an inspector: it must describe **the file**, not the subset that
/// survived a conversion. RealityKit convert bakes spec-gloss into metal-rough and expands
/// `EXT_mesh_gpu_instancing` into extra entities; neither may be reported as file truth.
public enum GLTFDocumentJSON {
    /// `fileURL` is only needed for binary payloads (texture thumbs, keyframe times when an
    /// animation input accessor omits `min`/`max`). Structure parses without it.
    public static func makeDocument(json: [String: Any], fileURL: URL? = nil) -> GLTFSessionDocument {
        makeDocument(json: json, binary: GLTFBinaryStore(json: json, fileURL: fileURL))
    }

    static func makeDocument(json: [String: Any], binary: GLTFBinaryStore) -> GLTFSessionDocument {
        let nodesJSON = json["nodes"] as? [[String: Any]] ?? []
        let meshesJSON = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let materialsJSON = json["materials"] as? [[String: Any]] ?? []

        let geometryByMesh = meshesJSON.map { meshGeometry($0, accessors: accessors) }
        let materialsByMesh = meshesJSON.map { boundMaterialIndices($0, materialCount: materialsJSON.count) }

        var document = GLTFSessionDocument()
        document.defaultSceneIndex = GLTFJSON.int(json["scene"]) ?? 0
        document.scenes = (json["scenes"] as? [[String: Any]] ?? []).map { scene in
            GLTFSessionDocument.Scene(
                name: scene["name"] as? String ?? "",
                rootNodeIndices: GLTFJSON.ints(scene["nodes"]).filter { nodesJSON.indices.contains($0) }
            )
        }
        let camerasJSON = json["cameras"] as? [[String: Any]] ?? []
        let lightsJSON = punctualLights(json)
        let skinsJSON = json["skins"] as? [[String: Any]] ?? []
        document.nodes = nodesJSON.enumerated().map { index, node in
            makeNode(
                node,
                index: index,
                counts: Counts(
                    nodes: nodesJSON.count,
                    meshes: meshesJSON.count,
                    cameras: camerasJSON.count,
                    lights: lightsJSON.count,
                    skins: skinsJSON.count
                ),
                geometryByMesh: geometryByMesh,
                materialsByMesh: materialsByMesh
            )
        }
        document.cameras = camerasJSON.map(makeCamera)
        document.lights = lightsJSON.map(makeLight)
        document.materials = materialsJSON.map(makeMaterial)
        document.skins = skinsJSON.enumerated().map { index, skin in
            makeSkin(skin, index: index, nodes: nodesJSON)
        }
        document.morphs = meshesJSON.enumerated().compactMap { index, mesh in
            makeMorph(mesh, meshIndex: index)
        }
        document.animations = (json["animations"] as? [[String: Any]] ?? []).compactMap { animation in
            makeAnimation(animation, accessors: accessors, binary: binary)
        }
        stampTexturePreviews(&document, json: json, materialsJSON: materialsJSON, binary: binary)
        return document
    }

    /// `KHR_materials_variants` names, in file order. Empty when the extension is absent.
    /// Read from JSON so the variant picker lists what the file declares, even for a
    /// variant the renderer cannot show.
    public static func materialVariantNames(json: [String: Any]) -> [String] {
        let extensions = json["extensions"] as? [String: Any] ?? [:]
        let variants = (extensions["KHR_materials_variants"] as? [String: Any])?["variants"]
        guard let entries = variants as? [[String: Any]], !entries.isEmpty else { return [] }
        return entries.enumerated().map { index, variant in
            let name = (variant["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "Variant \(index)" : name
        }
    }

    // MARK: - Nodes

    /// Array sizes used to reject out-of-range references — a malformed file must not
    /// give a node a kind whose backing entry does not exist.
    private struct Counts {
        var nodes = 0
        var meshes = 0
        var cameras = 0
        var lights = 0
        var skins = 0
    }

    private static func makeNode(
        _ node: [String: Any],
        index: Int,
        counts: Counts,
        geometryByMesh: [MeshGeometry],
        materialsByMesh: [[Int]]
    ) -> GLTFSessionDocument.Node {
        func reference(_ value: Any?, limit: Int) -> Int? {
            guard let index = GLTFJSON.int(value), index >= 0, index < limit else { return nil }
            return index
        }
        let meshIndex = reference(node["mesh"], limit: counts.meshes)
        let cameraIndex = reference(node["camera"], limit: counts.cameras)
        let lightIndex = reference(
            ((node["extensions"] as? [String: Any])?[lightsExtension] as? [String: Any])?["light"],
            limit: counts.lights
        )
        let skinIndex = reference(node["skin"], limit: counts.skins)
        let transform = decomposedTransform(node)
        let geometry = meshIndex.map { geometryByMesh[$0] } ?? MeshGeometry()
        return GLTFSessionDocument.Node(
            index: index,
            name: node["name"] as? String ?? "",
            children: GLTFJSON.ints(node["children"]).filter { $0 >= 0 && $0 < counts.nodes },
            kind: GLTFSessionDocument.Node.inferredKind(
                meshIndex: meshIndex,
                cameraIndex: cameraIndex,
                lightIndex: lightIndex,
                skinIndex: skinIndex
            ),
            translation: transform.translation,
            rotation: transform.rotation,
            scale: transform.scale,
            meshIndex: meshIndex,
            cameraIndex: cameraIndex,
            lightIndex: lightIndex,
            skinIndex: skinIndex,
            materialIndices: meshIndex.map { materialsByMesh[$0] } ?? [],
            triangleCount: geometry.triangleCount,
            vertexCount: geometry.vertexCount,
            uvSetCount: geometry.uvSetCount,
            hasNormals: geometry.hasNormals,
            hasTangents: geometry.hasTangents,
            hasVertexColors: geometry.hasVertexColors
        )
    }

    /// glTF nodes carry either TRS or a `matrix`; the sidebar always shows TRS.
    private static func decomposedTransform(
        _ node: [String: Any]
    ) -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        if let values = GLTFJSON.doubles(node["matrix"]), values.count == 16 {
            return decompose(matrix(from: values))
        }
        let translation = GLTFJSON.float3(node["translation"]) ?? .zero
        let scale = GLTFJSON.float3(node["scale"]) ?? .one
        var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if let values = GLTFJSON.doubles(node["rotation"]), values.count == 4 {
            rotation = simd_quatf(
                ix: Float(values[0]),
                iy: Float(values[1]),
                iz: Float(values[2]),
                r: Float(values[3])
            )
        }
        return (translation, rotation, scale)
    }

    private static func matrix(from values: [Double]) -> simd_float4x4 {
        let f = values.map(Float.init)
        return simd_float4x4(
            SIMD4<Float>(f[0], f[1], f[2], f[3]),
            SIMD4<Float>(f[4], f[5], f[6], f[7]),
            SIMD4<Float>(f[8], f[9], f[10], f[11]),
            SIMD4<Float>(f[12], f[13], f[14], f[15])
        )
    }

    private static func decompose(
        _ m: simd_float4x4
    ) -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        let translation = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        var basis = simd_float3x3(
            SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        )
        var scale = SIMD3<Float>(
            simd_length(basis.columns.0),
            simd_length(basis.columns.1),
            simd_length(basis.columns.2)
        )
        // A mirrored basis has no rotation-only form; fold the flip into X, as glTF tooling does.
        if simd_determinant(basis) < 0 {
            scale.x = -scale.x
        }
        for axis in 0..<3 where scale[axis] != 0 {
            basis[axis] /= scale[axis]
        }
        guard scale.x != 0, scale.y != 0, scale.z != 0 else {
            return (translation, simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale)
        }
        return (translation, simd_quatf(basis).normalized, scale)
    }

    // MARK: - Meshes

    struct MeshGeometry {
        var triangleCount = 0
        var vertexCount = 0
        var uvSetCount = 0
        var hasNormals = false
        var hasTangents = false
        var hasVertexColors = false
    }

    private static func meshGeometry(
        _ mesh: [String: Any],
        accessors: [[String: Any]]
    ) -> MeshGeometry {
        var stamp = MeshGeometry()
        var maxUV = 0
        for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
            let attributes = primitive["attributes"] as? [String: Any] ?? [:]
            stamp.vertexCount += GLTFJSON.accessorCount(attributes["POSITION"], accessors: accessors)
            if attributes["NORMAL"] != nil { stamp.hasNormals = true }
            if attributes["TANGENT"] != nil { stamp.hasTangents = true }
            if attributes.keys.contains(where: { $0.hasPrefix("COLOR_") }) { stamp.hasVertexColors = true }
            for uv in 0..<8 where attributes["TEXCOORD_\(uv)"] != nil {
                maxUV = max(maxUV, uv + 1)
            }
            stamp.triangleCount += GLTFJSON.triangleCount(primitive, accessors: accessors)
        }
        stamp.uvSetCount = maxUV
        return stamp
    }

    /// Unique material indices across a mesh's primitives, authoring order preserved.
    private static func boundMaterialIndices(_ mesh: [String: Any], materialCount: Int) -> [Int] {
        var seen = Set<Int>()
        var indices: [Int] = []
        for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
            guard let index = GLTFJSON.int(primitive["material"]),
                  index >= 0, index < materialCount,
                  seen.insert(index).inserted
            else { continue }
            indices.append(index)
        }
        return indices
    }

    private static func makeMorph(_ mesh: [String: Any], meshIndex: Int) -> GLTFSessionDocument.Morph? {
        let primitives = mesh["primitives"] as? [[String: Any]] ?? []
        let targetCount = primitives.map { ($0["targets"] as? [Any])?.count ?? 0 }.max() ?? 0
        guard targetCount > 0 else { return nil }
        let named = (mesh["extras"] as? [String: Any])?["targetNames"] as? [String] ?? []
        let targetNames = (0..<targetCount).map { index -> String in
            if index < named.count, !named[index].isEmpty { return named[index] }
            return "Morph\(index)"
        }
        return GLTFSessionDocument.Morph(
            meshIndex: meshIndex,
            meshName: mesh["name"] as? String ?? "Mesh\(meshIndex)",
            targetNames: targetNames
        )
    }

    // MARK: - Cameras and lights

    private static func makeCamera(_ camera: [String: Any]) -> GLTFSessionDocument.Camera {
        let name = camera["name"] as? String ?? ""
        if let ortho = camera["orthographic"] as? [String: Any],
           (camera["type"] as? String) != "perspective" {
            return GLTFSessionDocument.Camera(
                name: name,
                type: "orthographic",
                yfov: nil,
                znear: GLTFJSON.float(ortho["znear"]) ?? 0,
                zfar: GLTFJSON.float(ortho["zfar"]),
                xmag: GLTFJSON.float(ortho["xmag"]),
                ymag: GLTFJSON.float(ortho["ymag"])
            )
        }
        let perspective = camera["perspective"] as? [String: Any] ?? [:]
        return GLTFSessionDocument.Camera(
            name: name,
            type: "perspective",
            yfov: GLTFJSON.float(perspective["yfov"]),
            znear: GLTFJSON.float(perspective["znear"]) ?? 0,
            zfar: GLTFJSON.float(perspective["zfar"]),
            xmag: nil,
            ymag: nil
        )
    }

    private static let lightsExtension = "KHR_lights_punctual"

    private static func punctualLights(_ json: [String: Any]) -> [[String: Any]] {
        let extensions = json["extensions"] as? [String: Any] ?? [:]
        let punctual = extensions[lightsExtension] as? [String: Any] ?? [:]
        return punctual["lights"] as? [[String: Any]] ?? []
    }

    private static func makeLight(_ light: [String: Any]) -> GLTFSessionDocument.Light {
        let type = (light["type"] as? String)?.lowercased() ?? "directional"
        let isSpot = type == "spot"
        let spot = light["spot"] as? [String: Any] ?? [:]
        let range = GLTFJSON.float(light["range"])
        return GLTFSessionDocument.Light(
            name: light["name"] as? String ?? "",
            type: ["point", "spot", "directional"].contains(type) ? type : "directional",
            color: GLTFJSON.float3(light["color"]) ?? .one,
            intensity: GLTFJSON.float(light["intensity"]) ?? 1,
            // Directional light has no falloff; an absent or non-positive range is infinite.
            range: (type != "directional" && (range ?? 0) > 0) ? range : nil,
            innerCone: isSpot ? (GLTFJSON.float(spot["innerConeAngle"]) ?? 0) : nil,
            outerCone: isSpot ? (GLTFJSON.float(spot["outerConeAngle"]) ?? .pi / 4) : nil
        )
    }

    // MARK: - Materials

    private static let specGlossExtension = "KHR_materials_pbrSpecularGlossiness"

    private static func makeMaterial(_ material: [String: Any]) -> GLTFSessionDocument.Material {
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
    private static func stampTexturePreviews(
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

    // MARK: - Skins

    private static func makeSkin(
        _ skin: [String: Any],
        index: Int,
        nodes: [[String: Any]]
    ) -> GLTFSessionDocument.Skin {
        let joints = GLTFJSON.ints(skin["joints"]).filter { nodes.indices.contains($0) }
        var parentByNode: [Int: Int] = [:]
        for (nodeIndex, node) in nodes.enumerated() {
            for child in GLTFJSON.ints(node["children"]) where nodes.indices.contains(child) {
                parentByNode[child] = nodeIndex
            }
        }
        let jointNames = joints.enumerated().map { offset, nodeIndex in
            JointNames.resolved(nodes[nodeIndex]["name"] as? String, index: offset)
        }
        // Parent index is into *this skin's* joint list, not the node list; roots stay nil.
        let jointParentIndices: [Int?] = joints.map { nodeIndex in
            guard let parent = parentByNode[nodeIndex] else { return nil }
            return joints.firstIndex(of: parent)
        }
        let rawName = skin["name"] as? String ?? ""
        return GLTFSessionDocument.Skin(
            name: rawName.isEmpty ? "Skin\(index)" : rawName,
            jointNames: jointNames,
            jointNodeIndices: joints,
            jointParentIndices: jointParentIndices
        )
    }

    // MARK: - Animations

    /// Shortest span that still counts as a clip. Twin of `AnimationSampling.minimumDuration`,
    /// duplicated so the JSON path owes nothing to the converter.
    private static let minimumClipDuration: Float = 1e-4

    /// Same filter the playback path applies: a clip needs more than one keyframe and a
    /// non-trivial span, so one-keyframe "Default Take" junk never reaches the sidebar.
    private static func makeAnimation(
        _ animation: [String: Any],
        accessors: [[String: Any]],
        binary: GLTFBinaryStore
    ) -> GLTFSessionDocument.Animation? {
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        var sampleCount = 0
        for sampler in animation["samplers"] as? [[String: Any]] ?? [] {
            guard let inputIndex = GLTFJSON.int(sampler["input"]),
                  accessors.indices.contains(inputIndex)
            else { continue }
            let range = inputRange(accessors[inputIndex], binary: binary)
            sampleCount = max(sampleCount, range.count)
            if range.minTime.isFinite { minTime = min(minTime, range.minTime) }
            if range.maxTime.isFinite { maxTime = max(maxTime, range.maxTime) }
        }
        guard minTime.isFinite, maxTime.isFinite,
              sampleCount > 1,
              maxTime - minTime > minimumClipDuration
        else { return nil }
        let duration = Double(max(maxTime, 0))
        guard duration > 0 else { return nil }
        return GLTFSessionDocument.Animation(
            name: animation["name"] as? String ?? "",
            duration: duration
        )
    }

    /// Keyframe span of a sampler input. `min`/`max` are required on animation inputs, so
    /// the binary read is only a fallback for files that omit them.
    private static func inputRange(
        _ accessor: [String: Any],
        binary: GLTFBinaryStore
    ) -> (count: Int, minTime: Float, maxTime: Float) {
        let count = GLTFJSON.int(accessor["count"]) ?? 0
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        if let low = GLTFJSON.doubles(accessor["min"])?.first.map(Float.init), low.isFinite {
            minTime = low
        }
        if let high = GLTFJSON.doubles(accessor["max"])?.first.map(Float.init), high.isFinite {
            maxTime = high
        }
        if minTime.isFinite, maxTime.isFinite {
            return (count, minTime, maxTime)
        }
        guard let times = binary.scalarFloats(accessor: accessor) else {
            return (count, minTime, maxTime)
        }
        if let first = times.first, first.isFinite { minTime = min(minTime, first) }
        if let last = times.last, last.isFinite { maxTime = max(maxTime, last) }
        return (max(count, times.count), minTime, maxTime)
    }
}
