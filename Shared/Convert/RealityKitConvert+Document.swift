import GLTFKit2

extension RealityKitConvert {
    static func makeDocument(from asset: GLTFAsset) -> GLTFSessionDocument {
        var document = GLTFSessionDocument()
        document.defaultSceneIndex = asset.scenes.firstIndex(where: { $0 === asset.defaultScene }) ?? 0
        document.scenes = asset.scenes.map { scene in
            GLTFSessionDocument.Scene(
                name: scene.name ?? "",
                rootNodeIndices: scene.nodes.compactMap { identityIndex($0, in: asset.nodes) }
            )
        }
        let materialIndicesByMesh = asset.meshes.enumerated().map { index, mesh in
            (index, materialIndices(for: mesh, in: asset))
        }
        let materialIndicesLookup = Dictionary(uniqueKeysWithValues: materialIndicesByMesh)
        document.nodes = asset.nodes.enumerated().map { index, node in
            makeNode(node, index: index, asset: asset, materialIndicesByMesh: materialIndicesLookup)
        }
        document.cameras = asset.cameras.map(makeCamera)
        document.lights = asset.lights.map(makeLight)
        document.materials = asset.materials.map(makeMaterial)
        document.skins = asset.skins.enumerated().map { index, skin in
            makeSkin(skin, index: index, asset: asset)
        }
        document.morphs = asset.meshes.enumerated().compactMap { index, mesh in
            makeMorph(mesh, meshIndex: index)
        }
        document.animations = asset.animations.map(makeAnimation).filter { $0.duration > 0 }
        return document
    }

    static func makeNode(
        _ node: GLTFNode,
        index: Int,
        asset: GLTFAsset,
        materialIndicesByMesh: [Int: [Int]] = [:]
    ) -> GLTFSessionDocument.Node {
        let meshIndex = identityIndex(node.mesh, in: asset.meshes)
        let cameraIndex = identityIndex(node.camera, in: asset.cameras)
        let lightIndex = identityIndex(node.light, in: asset.lights)
        let skinIndex = identityIndex(node.skin, in: asset.skins)
        let materialIndices = meshIndex.flatMap { materialIndicesByMesh[$0] } ?? []
        return GLTFSessionDocument.Node(
            index: index,
            name: node.name ?? "",
            children: node.childNodes.compactMap { identityIndex($0, in: asset.nodes) },
            kind: GLTFSessionDocument.Node.inferredKind(
                meshIndex: meshIndex,
                cameraIndex: cameraIndex,
                lightIndex: lightIndex,
                skinIndex: skinIndex
            ),
            translation: node.translation,
            rotation: node.rotation,
            scale: node.scale,
            meshIndex: meshIndex,
            cameraIndex: cameraIndex,
            lightIndex: lightIndex,
            skinIndex: skinIndex,
            materialIndices: materialIndices
        )
    }

    /// Unique file material indices for a mesh's primitives (order preserved).
    private static func materialIndices(for mesh: GLTFMesh, in asset: GLTFAsset) -> [Int] {
        var seen = Set<Int>()
        var indices: [Int] = []
        for primitive in mesh.primitives {
            guard let materialIndex = resolvedMaterialIndex(primitive.material, in: asset.materials) else {
                continue
            }
            if seen.insert(materialIndex).inserted {
                indices.append(materialIndex)
            }
        }
        return indices
    }

    private static func resolvedMaterialIndex(
        _ material: GLTFMaterial?,
        in materials: [GLTFMaterial]
    ) -> Int? {
        if let index = identityIndex(material, in: materials) {
            return index
        }
        guard let material, let name = material.name, !name.isEmpty else { return nil }
        return materials.firstIndex { $0.name == name }
    }

    static func makeCamera(_ camera: GLTFCamera) -> GLTFSessionDocument.Camera {
        let name = camera.name ?? ""
        let zfar = camera.zFar.isFinite ? camera.zFar : nil
        if let perspective = camera.perspective {
            return GLTFSessionDocument.Camera(
                name: name,
                type: "perspective",
                yfov: perspective.yFOV,
                znear: camera.zNear,
                zfar: zfar,
                xmag: nil,
                ymag: nil
            )
        }
        return GLTFSessionDocument.Camera(
            name: name,
            type: "orthographic",
            yfov: nil,
            znear: camera.zNear,
            zfar: zfar,
            xmag: camera.orthographic?.xMag,
            ymag: camera.orthographic?.yMag
        )
    }

    static func makeLight(_ light: GLTFLight) -> GLTFSessionDocument.Light {
        let type: String
        switch light.type {
        case .point: type = "point"
        case .spot: type = "spot"
        default: type = "directional"
        }
        let isSpot = type == "spot"
        let range: Float? = (type != "directional" && light.range > 0) ? light.range : nil
        return GLTFSessionDocument.Light(
            name: light.name ?? "",
            type: type,
            color: light.color,
            intensity: light.intensity,
            range: range,
            innerCone: isSpot ? light.innerConeAngle : nil,
            outerCone: isSpot ? light.outerConeAngle : nil
        )
    }

    static func makeMaterial(_ material: GLTFMaterial) -> GLTFSessionDocument.Material {
        let workflow: GLTFSessionDocument.Material.Workflow
        if material.isUnlit {
            workflow = .unlit
        } else {
            workflow = .metallicRoughness
        }
        let alphaMode: GLTFSessionDocument.Material.AlphaMode
        switch material.alphaMode {
        case .mask: alphaMode = .mask
        case .blend: alphaMode = .blend
        default: alphaMode = .opaque
        }
        let metallic = material.metallicRoughness
        return GLTFSessionDocument.Material(
            name: material.name ?? "",
            maps: MaterialMapPresence.from(gltf: material),
            workflow: workflow,
            alphaMode: alphaMode,
            isDoubleSided: material.isDoubleSided,
            metallicFactor: metallic?.metallicFactor,
            roughnessFactor: metallic?.roughnessFactor,
            alphaCutoff: alphaMode == .mask ? material.alphaCutoff : nil
        )
    }

    static func makeSkin(_ skin: GLTFSkin, index: Int, asset: GLTFAsset) -> GLTFSessionDocument.Skin {
        let jointNames = skin.joints.enumerated().map { jointIndex, joint in
            Skin.resolvedName(joint.name, index: jointIndex)
        }
        let jointNodeIndices = skin.joints.compactMap { identityIndex($0, in: asset.nodes) }
        let jointParentIndices: [Int?] = skin.joints.map { joint in
            guard let parent = joint.parent else { return nil }
            return skin.joints.firstIndex(of: parent)
        }
        let rawName = skin.name ?? ""
        return GLTFSessionDocument.Skin(
            name: rawName.isEmpty ? "Skin\(index)" : rawName,
            jointNames: jointNames,
            jointNodeIndices: jointNodeIndices,
            jointParentIndices: jointParentIndices
        )
    }

    static func makeMorph(_ mesh: GLTFMesh, meshIndex: Int) -> GLTFSessionDocument.Morph? {
        let targetCount = mesh.primitives.map(\.targets.count).max() ?? 0
        guard targetCount > 0 else { return nil }
        let named = mesh.targetNames ?? []
        let targetNames = (0..<targetCount).map { index -> String in
            if index < named.count, !named[index].isEmpty {
                return named[index]
            }
            return "Morph\(index)"
        }
        return GLTFSessionDocument.Morph(
            meshIndex: meshIndex,
            meshName: mesh.name ?? "Mesh\(meshIndex)",
            targetNames: targetNames
        )
    }

    static func makeAnimation(_ animation: GLTFAnimation) -> GLTFSessionDocument.Animation {
        GLTFSessionDocument.Animation(
            name: animation.name ?? "",
            duration: AnimationSampling.documentedDuration(animation)
        )
    }

    /// Identity (`===`) index into a GLTFKit2 object array; nil when the ref is nil or absent.
    private static func identityIndex<T: AnyObject>(_ object: T?, in collection: [T]) -> Int? {
        guard let object else { return nil }
        return collection.firstIndex { $0 === object }
    }
}
