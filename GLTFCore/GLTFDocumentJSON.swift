import Foundation
import simd

/// Builds `GLTFDocument` from the glTF JSON itself, no renderer in the call path.
///
/// The sidebar is an inspector: it describes **the file** as authored (spec-gloss stays
/// spec-gloss, an instanced mesh stays one node).
public enum GLTFDocumentJSON {
    enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidNumeric(String)
        case invalidResource(String)

        var errorDescription: String? {
            switch self {
            case .invalidNumeric(let message), .invalidResource(let message):
                return "The glTF document is malformed: \(message)"
            }
        }
    }

    static func validate(json: [String: Any], fileURL: URL?) throws {
        guard let asset = json["asset"] as? [String: Any],
              asset["version"] as? String == "2.0"
        else {
            throw Error.invalidNumeric("Only glTF version 2.0 is supported.")
        }

        let integerFields = [
            "scene", "buffer", "byteOffset", "byteLength", "byteStride", "bufferView",
            "componentType", "count", "mesh", "camera", "skin", "material", "mode",
            "source", "sampler", "input", "output", "node", "skeleton", "inverseBindMatrices",
        ]
        let integerArrayFields = ["children", "nodes", "joints", "variants"]
        let numberArrayFields = [
            "min", "max", "matrix", "translation", "rotation", "scale", "color",
            "emissiveFactor", "weights",
        ]
        // Custom metadata and unknown extensions are opaque to this reader. Their field
        // names may coincide with core glTF fields without sharing their types.
        let inspectedExtensions: Set<String> = [
            "KHR_lights_punctual", "KHR_materials_variants", "EXT_mesh_gpu_instancing",
            "KHR_node_visibility",
        ]
        func check(_ object: Any, key: String? = nil, parentKey: String? = nil) throws {
            if key == "extras" { return }
            // Normal texture strength is a scalar; node and texture-transform scale
            // use arrays. Match the containing property before the generic array check.
            if key == "scale", parentKey == "normalTexture" || parentKey == "clearcoatNormalTexture" {
                guard GLTFJSON.double(object) != nil else {
                    throw Error.invalidNumeric("The normal texture scale is not a valid number.")
                }
                return
            }
            if key == "extensions", let extensions = object as? [String: Any] {
                for (name, value) in extensions where inspectedExtensions.contains(name) {
                    try check(value)
                }
                return
            }
            if let key, integerFields.contains(key) {
                guard GLTFJSON.int(object) != nil else {
                    throw Error.invalidNumeric("The \(key) value is not a valid integer.")
                }
                if let number = GLTFJSON.int(object), number < 0 {
                    throw Error.invalidNumeric("The \(key) value cannot be negative.")
                }
            }
            if let key, integerArrayFields.contains(key) {
                guard let values = object as? [Any],
                      (key == "nodes" || key == "variants") && values.allSatisfy({ $0 is [String: Any] })
                        || values.allSatisfy({ GLTFJSON.int($0) != nil })
                else {
                    throw Error.invalidNumeric("The \(key) array contains an invalid integer.")
                }
            }
            if let key, numberArrayFields.contains(key) {
                guard let values = object as? [Any], values.allSatisfy({ GLTFJSON.double($0) != nil }) else {
                    throw Error.invalidNumeric("The \(key) array contains an invalid number.")
                }
            }
            if let object = object as? [String: Any] {
                for (childKey, value) in object { try check(value, key: childKey, parentKey: key) }
            } else if let object = object as? [[String: Any]] {
                for value in object { try check(value) }
            } else if let object = object as? [Any] {
                for value in object { try check(value) }
            }
        }
        try check(json)
        try GLTFBinaryStore(json: json, fileURL: fileURL).validateResources()
    }

    /// `fileURL` is only needed for binary payloads (texture thumbs, keyframe times when an
    /// animation input accessor omits `min`/`max`). Structure parses without it.
    public static func makeDocument(json: [String: Any], fileURL: URL? = nil) -> GLTFDocument {
        makeDocument(json: json, binary: GLTFBinaryStore(json: json, fileURL: fileURL))
    }

    static func makeDocument(json: [String: Any], binary: GLTFBinaryStore) -> GLTFDocument {
        let interval = AppLog.signposter.beginInterval("json.document")
        defer { AppLog.signposter.endInterval("json.document", interval) }

        let nodesJSON = json["nodes"] as? [[String: Any]] ?? []
        let meshesJSON = json["meshes"] as? [[String: Any]] ?? []
        let accessors = json["accessors"] as? [[String: Any]] ?? []
        let materialsJSON = json["materials"] as? [[String: Any]] ?? []

        let geometryByMesh = meshesJSON.map { meshGeometry($0, accessors: accessors) }
        let primitivesByMesh = meshesJSON.map { meshPrimitives($0, accessors: accessors, materialCount: materialsJSON.count) }
        let materialsByMesh = meshesJSON.map { boundMaterialIndices($0, materialCount: materialsJSON.count) }

        var document = GLTFDocument()
        document.defaultSceneIndex = GLTFJSON.int(json["scene"]) ?? 0
        document.bounds = ModelBounds.from(json: json)
        document.materialVariantNames = materialVariantNames(json: json)
        document.viewModes = ViewModeAvailability(json: json).viewModes
        document.scenes = (json["scenes"] as? [[String: Any]] ?? []).map { scene in
            GLTFDocument.Scene(
                name: scene["name"] as? String ?? "",
                rootNodeIndices: GLTFJSON.ints(scene["nodes"]).filter { nodesJSON.indices.contains($0) }
            )
        }
        let camerasJSON = json["cameras"] as? [[String: Any]] ?? []
        let lightsJSON = punctualLights(json)
        let skinsJSON = json["skins"] as? [[String: Any]] ?? []
        let counts = Counts(
            nodes: nodesJSON.count,
            meshes: meshesJSON.count,
            cameras: camerasJSON.count,
            lights: lightsJSON.count,
            skins: skinsJSON.count
        )
        document.nodes = AppLog.signposter.withIntervalSignpost("json.document.nodes") {
            makeNodes(
                nodesJSON,
                counts: counts,
                accessors: accessors,
                geometryByMesh: geometryByMesh,
                primitivesByMesh: primitivesByMesh,
                materialsByMesh: materialsByMesh
            )
        }
        document.cameras = camerasJSON.map(makeCamera)
        document.lights = lightsJSON.map(makeLight)
        document.materials = materialsJSON.map(makeMaterial)
        document.meshPrimitiveMaterials = meshesJSON.map { mesh in
            (mesh["primitives"] as? [[String: Any]] ?? []).map { primitive in
                GLTFJSON.int(primitive["material"]).flatMap {
                    materialsJSON.indices.contains($0) ? $0 : nil
                }
            }
        }
        if !skinsJSON.isEmpty {
            document.skins = AppLog.signposter.withIntervalSignpost("json.document.skins") {
                skinsJSON.enumerated().map { index, skin in
                    makeSkin(skin, index: index, nodes: nodesJSON)
                }
            }
            stampJointMembership(&document)
            stampSkinnedMeshes(&document, meshes: meshesJSON)
        }
        document.morphs = meshesJSON.enumerated().compactMap { index, mesh in
            makeMorph(mesh, meshIndex: index)
        }
        document.animations = (json["animations"] as? [[String: Any]] ?? []).map { animation in
            makeAnimation(animation, accessors: accessors, nodes: nodesJSON, binary: binary)
        }
        AppLog.signposter.withIntervalSignpost("json.document.textures") {
            stampTexturePreviews(&document, json: json, materialsJSON: materialsJSON, binary: binary)
        }
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

    private static func makeNodes(
        _ nodesJSON: [[String: Any]],
        counts: Counts,
        accessors: [[String: Any]],
        geometryByMesh: [MeshGeometry],
        primitivesByMesh: [[GLTFDocument.MeshPrimitive]],
        materialsByMesh: [[Int]]
    ) -> [GLTFDocument.Node] {
        let count = nodesJSON.count
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            makeNode(
                nodesJSON[index],
                index: index,
                counts: counts,
                accessors: accessors,
                geometryByMesh: geometryByMesh,
                primitivesByMesh: primitivesByMesh,
                materialsByMesh: materialsByMesh
            )
        }
    }

    private enum NodeKey {
        static let mesh = "mesh" as NSString
        static let camera = "camera" as NSString
        static let name = "name" as NSString
        static let children = "children" as NSString
        static let matrix = "matrix" as NSString
        static let translation = "translation" as NSString
        static let rotation = "rotation" as NSString
        static let scale = "scale" as NSString
        static let skin = "skin" as NSString
        static let extensions = "extensions" as NSString
        static let light = "light" as NSString
        static let visible = "visible" as NSString
    }

    private static func makeNode(
        _ node: [String: Any],
        index: Int,
        counts: Counts,
        accessors: [[String: Any]],
        geometryByMesh: [MeshGeometry],
        primitivesByMesh: [[GLTFDocument.MeshPrimitive]],
        materialsByMesh: [[Int]]
    ) -> GLTFDocument.Node {
        let dict = node as NSDictionary
        func reference(_ value: Any?, limit: Int) -> Int? {
            guard let index = GLTFJSON.int(value), index >= 0, index < limit else { return nil }
            return index
        }
        let meshIndex = counts.meshes == 0 ? nil : reference(dict.object(forKey: NodeKey.mesh), limit: counts.meshes)
        let cameraIndex = counts.cameras == 0
            ? nil
            : reference(dict.object(forKey: NodeKey.camera), limit: counts.cameras)
        let lightIndex = counts.lights == 0
            ? nil
            : reference(punctualLightIndex(dict), limit: counts.lights)
        let skinIndex = counts.skins == 0 ? nil : reference(dict.object(forKey: NodeKey.skin), limit: counts.skins)
        let transform = decomposedTransform(dict)
        let geometry = meshIndex.map { geometryByMesh[$0] } ?? MeshGeometry()
        return GLTFDocument.Node(
            index: index,
            name: dict.object(forKey: NodeKey.name) as? String ?? "",
            children: GLTFJSON.ints(dict.object(forKey: NodeKey.children))
                .filter { $0 >= 0 && $0 < counts.nodes },
            kind: GLTFDocument.Node.inferredKind(
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
            hasTangents: geometry.hasTangents,
            hasVertexColors: geometry.hasVertexColors,
            meshPrimitives: meshIndex.map { primitivesByMesh[$0] } ?? [],
            gpuInstanceCount: gpuInstanceCount(dict, accessors: accessors),
            isHiddenInFile: isHiddenInFile(dict)
        )
    }

    private static func isHiddenInFile(_ node: NSDictionary) -> Bool {
        let extensions = node.object(forKey: NodeKey.extensions) as? NSDictionary
        let visibility = extensions?.object(forKey: visibilityExtension) as? NSDictionary
        return (visibility?.object(forKey: NodeKey.visible) as? Bool) == false
    }

    private static func punctualLightIndex(_ node: NSDictionary) -> Any? {
        let extensions = node.object(forKey: NodeKey.extensions) as? NSDictionary
        let punctual = extensions?.object(forKey: lightsExtension) as? NSDictionary
        return punctual?.object(forKey: NodeKey.light)
    }

    /// glTF nodes carry either TRS or a `matrix`; the sidebar always shows TRS.
    private static func decomposedTransform(
        _ node: NSDictionary
    ) -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        if let matrix = GLTFJSON.float4x4(node.object(forKey: NodeKey.matrix)) {
            return decompose(matrix)
        }
        let translation = GLTFJSON.float3(node.object(forKey: NodeKey.translation)) ?? .zero
        let scale = GLTFJSON.float3(node.object(forKey: NodeKey.scale)) ?? .one
        var rotation = identityRotation
        if let values = GLTFJSON.float4(node.object(forKey: NodeKey.rotation)) {
            rotation = simd_quatf(ix: values.x, iy: values.y, iz: values.z, r: values.w)
        }
        return (translation, rotation, scale)
    }

    private static let identityRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    private static func decompose(
        _ m: simd_float4x4
    ) -> (translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        let translation = SIMD3<Float>(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        let c0 = SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z)
        let c1 = SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z)
        let c2 = SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)
        // Instance dumps are mostly +axis scale + translation; skip the quat for those.
        if c0.y == 0, c0.z == 0, c1.x == 0, c1.z == 0, c2.x == 0, c2.y == 0,
           c0.x > 0, c1.y > 0, c2.z > 0 {
            return (translation, identityRotation, SIMD3<Float>(c0.x, c1.y, c2.z))
        }
        var basis = simd_float3x3(c0, c1, c2)
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
        var hasTangents = false
        var hasVertexColors = false
    }

    private static func materialVariantMappings(_ primitive: [String: Any], materialCount: Int) -> [GLTFDocument.MaterialVariantMapping] {
        let extensions = primitive["extensions"] as? [String: Any] ?? [:]
        let payload = extensions["KHR_materials_variants"] as? [String: Any] ?? [:]
        let entries = payload["mappings"] as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            let variants = (entry["variants"] as? [Any])?.compactMap { GLTFJSON.int($0) } ?? []
            guard !variants.isEmpty,
                  let material = GLTFJSON.int(entry["material"]),
                  material >= 0, material < materialCount
            else { return nil }
            return GLTFDocument.MaterialVariantMapping(variantIndices: variants, materialIndex: material)
        }
    }

    private static func meshPrimitives(
        _ mesh: [String: Any],
        accessors: [[String: Any]],
        materialCount: Int
    ) -> [GLTFDocument.MeshPrimitive] {
        (mesh["primitives"] as? [[String: Any]] ?? []).map { primitive in
            let material = GLTFJSON.int(primitive["material"]).flatMap {
                $0 >= 0 && $0 < materialCount ? $0 : nil
            }
            let mode = GLTFJSON.int(primitive["mode"]) ?? 4
            let variantMappings = materialVariantMappings(primitive, materialCount: materialCount)
            return GLTFDocument.MeshPrimitive(
                materialIndex: material,
                variantMappings: variantMappings,
                triangleCount: GLTFJSON.triangleCount(primitive, accessors: accessors),
                mode: mode
            )
        }
    }

    private static func gpuInstanceCount(_ node: NSDictionary, accessors: [[String: Any]]) -> Int? {
        let extensions = node.object(forKey: NodeKey.extensions) as? NSDictionary
        let instancing = extensions?.object(forKey: gpuInstancingExtension) as? NSDictionary
        let attributes = instancing?.object(forKey: "attributes") as? NSDictionary
        guard let attributes, attributes.count > 0 else { return nil }
        for key in ["TRANSLATION", "ROTATION", "SCALE"] as [NSString] {
            if let index = GLTFJSON.int(attributes.object(forKey: key)),
               accessors.indices.contains(index),
               let count = GLTFJSON.int(accessors[index]["count"]),
               count > 0 {
                return count
            }
        }
        for key in attributes.allKeys {
            guard let index = GLTFJSON.int(attributes.object(forKey: key)),
                  accessors.indices.contains(index),
                  let count = GLTFJSON.int(accessors[index]["count"]),
                  count > 0
            else { continue }
            return count
        }
        return nil
    }

    private static func stampJointMembership(_ document: inout GLTFDocument) {
        for skinIndex in document.skins.indices {
            for joint in document.skins[skinIndex].jointNodeIndices where document.nodes.indices.contains(joint) {
                document.nodes[joint].jointOfSkinIndices.append(skinIndex)
            }
        }
    }

    private static func meshGeometry(
        _ mesh: [String: Any],
        accessors: [[String: Any]]
    ) -> MeshGeometry {
        var stamp = MeshGeometry()
        var maxUV = 0
        var countedPositionAccessors = Set<Int>()
        for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
            let attributes = primitive["attributes"] as? [String: Any] ?? [:]
            if let position = GLTFJSON.int(attributes["POSITION"]),
               position >= 0, position < accessors.count,
               countedPositionAccessors.insert(position).inserted {
                stamp.vertexCount += GLTFJSON.accessorCount(attributes["POSITION"], accessors: accessors)
            }
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

    /// The attributes a target may displace, in the order the inspector lists them.
    private static let morphAttributeOrder = ["POSITION", "NORMAL", "TANGENT"]

    private static func makeMorph(_ mesh: [String: Any], meshIndex: Int) -> GLTFDocument.Morph? {
        let primitives = mesh["primitives"] as? [[String: Any]] ?? []
        let targetCount = primitives.map { ($0["targets"] as? [Any])?.count ?? 0 }.max() ?? 0
        guard targetCount > 0 else { return nil }
        let named = (mesh["extras"] as? [String: Any])?["targetNames"] as? [String] ?? []
        let targetNames = (0..<targetCount).map { index -> String in
            if index < named.count, !named[index].isEmpty { return named[index] }
            return "Morph\(index)"
        }
        let targeted = primitives.compactMap { primitive -> [[String: Any]]? in
            let targets = primitive["targets"] as? [[String: Any]] ?? []
            return targets.isEmpty ? nil : targets
        }
        let present = Set(targeted.joined().flatMap(\.keys))
        let attributes = morphAttributeOrder.filter(present.contains)
        let primitiveCount = targeted.count
        return GLTFDocument.Morph(
            meshIndex: meshIndex,
            meshName: mesh["name"] as? String ?? "Mesh\(meshIndex)",
            targetNames: targetNames,
            targetAttributes: attributes,
            defaultWeights: (GLTFJSON.doubles(mesh["weights"]) ?? []).map(Float.init),
            primitiveCount: primitiveCount
        )
    }

    // MARK: - Cameras and lights

    private static func makeCamera(_ camera: [String: Any]) -> GLTFDocument.Camera {
        let name = camera["name"] as? String ?? ""
        if let ortho = camera["orthographic"] as? [String: Any],
           (camera["type"] as? String) != "perspective" {
            return GLTFDocument.Camera(
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
        return GLTFDocument.Camera(
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
    private static let visibilityExtension = "KHR_node_visibility"
    private static let gpuInstancingExtension = "EXT_mesh_gpu_instancing"

    private static func punctualLights(_ json: [String: Any]) -> [[String: Any]] {
        let extensions = json["extensions"] as? [String: Any] ?? [:]
        let punctual = extensions[lightsExtension] as? [String: Any] ?? [:]
        return punctual["lights"] as? [[String: Any]] ?? []
    }

    private static func makeLight(_ light: [String: Any]) -> GLTFDocument.Light {
        let type = (light["type"] as? String)?.lowercased() ?? "directional"
        let isSpot = type == "spot"
        let spot = light["spot"] as? [String: Any] ?? [:]
        let range = GLTFJSON.float(light["range"])
        return GLTFDocument.Light(
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

    // MARK: - Skins

    /// Unnamed joints are `joint-<position in the skin>`.
    private static func makeSkin(
        _ skin: [String: Any],
        index: Int,
        nodes: [[String: Any]]
    ) -> GLTFDocument.Skin {
        let joints = GLTFJSON.ints(skin["joints"]).filter { nodes.indices.contains($0) }
        let jointNames = joints.enumerated().map { offset, nodeIndex in
            let name = nodes[nodeIndex]["name"] as? String ?? ""
            return name.isEmpty ? "joint-\(offset)" : name
        }
        let rawName = skin["name"] as? String ?? ""
        return GLTFDocument.Skin(
            name: rawName.isEmpty ? "Skin\(index)" : rawName,
            jointNames: jointNames,
            jointNodeIndices: joints,
            skeletonNodeIndex: GLTFJSON.int(skin["skeleton"]).flatMap { nodes.indices.contains($0) ? $0 : nil },
            storesInverseBindMatrices: GLTFJSON.int(skin["inverseBindMatrices"]) != nil
        )
    }

    /// The widest `JOINTS_n` run one mesh's primitives declare: four weights per set.
    private static func jointSetCount(_ mesh: [String: Any]) -> Int {
        var widest = 0
        for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
            let attributes = primitive["attributes"] as? [String: Any] ?? [:]
            var sets = 0
            while attributes["JOINTS_\(sets)"] != nil { sets += 1 }
            widest = max(widest, sets)
        }
        return widest
    }

    /// Which meshes each skin deforms, from the parsed nodes rather than the raw JSON: `Node`
    /// already carries range-checked `skinIndex` / `meshIndex`, so one walk settles every skin.
    private static func stampSkinnedMeshes(_ document: inout GLTFDocument, meshes: [[String: Any]]) {
        guard !document.skins.isEmpty else { return }
        // One `JOINTS_n` probe per mesh, not per node that points at it.
        var jointSets: [Int: Int] = [:]
        var seen: [Set<Int>] = Array(repeating: [], count: document.skins.count)
        for node in document.nodes {
            guard let skinIndex = node.skinIndex, document.skins.indices.contains(skinIndex),
                  let meshIndex = node.meshIndex, meshes.indices.contains(meshIndex),
                  seen[skinIndex].insert(meshIndex).inserted
            else { continue }
            let mesh = meshes[meshIndex]
            let name = (mesh["name"] as? String ?? "")
            document.skins[skinIndex].skinnedMeshNames.append(name.isEmpty ? "Mesh \(meshIndex)" : name)
            let sets = jointSets[meshIndex] ?? {
                let count = jointSetCount(mesh)
                jointSets[meshIndex] = count
                return count
            }()
            document.skins[skinIndex].influenceSetCount =
                max(document.skins[skinIndex].influenceSetCount, sets)
        }
    }

    // MARK: - Animations

    /// Shortest span that still counts as a clip.
    private static let minimumClipDuration: Float = 1e-4

    /// A clip needs more than one keyframe and a non-trivial span; one-keyframe "Default Take"
    /// junk gets duration 0, which the outliner leaves out.
    private static func makeAnimation(
        _ animation: [String: Any],
        accessors: [[String: Any]],
        nodes: [[String: Any]],
        binary: GLTFBinaryStore
    ) -> GLTFDocument.Animation {
        let samplers = animation["samplers"] as? [[String: Any]] ?? []
        var minTime = Float.infinity
        var maxTime = -Float.infinity
        var sampleCount = 0
        for sampler in samplers {
            guard let inputIndex = GLTFJSON.int(sampler["input"]),
                  accessors.indices.contains(inputIndex)
            else { continue }
            let range = inputRange(accessors[inputIndex], binary: binary)
            sampleCount = max(sampleCount, range.count)
            if range.minTime.isFinite { minTime = min(minTime, range.minTime) }
            if range.maxTime.isFinite { maxTime = max(maxTime, range.maxTime) }
        }
        let isClip = minTime.isFinite && maxTime.isFinite && sampleCount > 1 && maxTime - minTime > minimumClipDuration

        // Channels name what moves; only the ones that resolve to a node in this file count, so a
        // dangling channel never inflates the readout.
        var channelCount = 0
        var targets: [Int] = []
        var seenTargets = Set<Int>()
        var paths: Set<GLTFDocument.Animation.Path> = []
        var interpolations: Set<GLTFDocument.Animation.Interpolation> = []
        for channel in animation["channels"] as? [[String: Any]] ?? [] {
            let target = channel["target"] as? [String: Any] ?? [:]
            guard let node = GLTFJSON.int(target["node"]), nodes.indices.contains(node) else { continue }
            channelCount += 1
            if seenTargets.insert(node).inserted { targets.append(node) }
            if let raw = target["path"] as? String,
               let path = GLTFDocument.Animation.Path(rawValue: raw) {
                paths.insert(path)
            }
            if let samplerIndex = GLTFJSON.int(channel["sampler"]), samplers.indices.contains(samplerIndex) {
                // `interpolation` is optional; the spec default is LINEAR.
                let raw = samplers[samplerIndex]["interpolation"] as? String ?? "LINEAR"
                if let interpolation = GLTFDocument.Animation.Interpolation(rawValue: raw) {
                    interpolations.insert(interpolation)
                }
            }
        }
        return GLTFDocument.Animation(
            name: animation["name"] as? String ?? "",
            duration: isClip ? Double(maxTime - minTime) : 0,
            channelCount: channelCount,
            keyframeCount: sampleCount,
            targetNodeIndices: targets,
            // Each enum's own case order, so the readout is stable whatever order the file lists:
            // TRS then weights for paths.
            paths: GLTFDocument.Animation.Path.allCases.filter(paths.contains),
            interpolations: GLTFDocument.Animation.Interpolation.allCases.filter(interpolations.contains)
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
