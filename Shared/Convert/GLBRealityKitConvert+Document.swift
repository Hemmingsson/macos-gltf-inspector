import GLTFKit2
import simd

extension GLBRealityKitConvert {
    static func makeDocument(from asset: GLTFAsset) -> GLTFSessionDocument {
        var document = GLTFSessionDocument()
        document.defaultSceneIndex = asset.scenes.firstIndex(where: { $0 === asset.defaultScene }) ?? 0
        document.scenes = asset.scenes.map { scene in
            GLTFSessionDocument.Scene(
                name: scene.name ?? "",
                rootNodeIndices: scene.nodes.compactMap { node in
                    asset.nodes.firstIndex(where: { $0 === node })
                }
            )
        }
        document.nodes = asset.nodes.enumerated().map { index, node in
            makeNode(node, index: index, asset: asset)
        }
        document.meshes = asset.meshes.enumerated().map { _, mesh in
            makeMesh(mesh, asset: asset)
        }
        document.materials = asset.materials.map(makeMaterial)
        document.lights = asset.lights.map(makeLight)
        document.cameras = asset.cameras.map(makeCamera)
        document.animations = asset.animations.map(makeAnimation).filter { $0.duration > 0 }
        return document
    }

    static func makeNode(_ node: GLTFNode, index: Int, asset: GLTFAsset) -> GLTFSessionDocument.Node {
        GLTFSessionDocument.Node(
            index: index,
            name: node.name ?? "",
            children: node.childNodes.compactMap { child in
                asset.nodes.firstIndex(where: { $0 === child })
            },
            meshIndex: node.mesh.flatMap { mesh in
                asset.meshes.firstIndex(where: { $0 === mesh })
            },
            cameraIndex: node.camera.flatMap { camera in
                asset.cameras.firstIndex(where: { $0 === camera })
            },
            lightIndex: node.light.flatMap { light in
                asset.lights.firstIndex(where: { $0 === light })
            },
            translation: node.translation,
            rotation: node.rotation.vector,
            scale: node.scale
        )
    }

    static func makeMesh(_ mesh: GLTFMesh, asset: GLTFAsset) -> GLTFSessionDocument.Mesh {
        var triangleCount = 0
        var vertexCount = 0
        var materialIndices: [Int] = []
        for primitive in mesh.primitives {
            let verts = primitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            vertexCount += verts
            if let indexCount = primitive.indices?.count {
                triangleCount += primitive.primitiveType == .triangles ? indexCount / 3 : 0
            } else if primitive.primitiveType == .triangles {
                triangleCount += verts / 3
            }
            if let material = primitive.material,
               let materialIndex = asset.materials.firstIndex(where: { $0 === material }) {
                materialIndices.append(materialIndex)
            }
        }
        return GLTFSessionDocument.Mesh(
            name: mesh.name ?? "",
            primitiveCount: mesh.primitives.count,
            triangleCount: triangleCount,
            vertexCount: vertexCount,
            materialIndices: materialIndices
        )
    }

    static func makeMaterial(_ material: GLTFMaterial) -> GLTFSessionDocument.Material {
        let metallicRoughness = material.metallicRoughness
        let alphaMode: String
        switch material.alphaMode {
        case .mask:
            alphaMode = "MASK"
        case .blend:
            alphaMode = "BLEND"
        default:
            alphaMode = "OPAQUE"
        }
        return GLTFSessionDocument.Material(
            name: material.name ?? "",
            baseColorFactor: metallicRoughness?.baseColorFactor ?? SIMD4(1, 1, 1, 1),
            metallicFactor: metallicRoughness?.metallicFactor ?? 1,
            roughnessFactor: metallicRoughness?.roughnessFactor ?? 1,
            emissiveFactor: material.emissive?.emissiveFactor ?? .zero,
            alphaMode: alphaMode,
            hasBaseColorTexture: metallicRoughness?.baseColorTexture != nil,
            hasMetallicRoughnessTexture: metallicRoughness?.metallicRoughnessTexture != nil,
            hasNormalTexture: material.normalTexture != nil,
            hasOcclusionTexture: material.occlusionTexture != nil,
            hasEmissiveTexture: material.emissive?.emissiveTexture != nil
        )
    }

    static func makeLight(_ light: GLTFLight) -> GLTFSessionDocument.Light {
        let type: String
        switch light.type {
        case .directional:
            type = "directional"
        case .point:
            type = "point"
        case .spot:
            type = "spot"
        default:
            type = "unknown"
        }
        return GLTFSessionDocument.Light(
            name: light.name ?? "",
            type: type,
            color: light.color,
            intensity: light.intensity,
            range: light.range > 0 ? light.range : nil,
            innerCone: light.type == .spot ? light.innerConeAngle : nil,
            outerCone: light.type == .spot ? light.outerConeAngle : nil
        )
    }

    static func makeCamera(_ camera: GLTFCamera) -> GLTFSessionDocument.Camera {
        let zfar = camera.zFar.isFinite ? camera.zFar : nil
        if let perspective = camera.perspective {
            return GLTFSessionDocument.Camera(
                name: camera.name ?? "",
                type: "perspective",
                yfov: perspective.yFOV,
                znear: camera.zNear,
                zfar: zfar,
                xmag: nil,
                ymag: nil
            )
        }
        return GLTFSessionDocument.Camera(
            name: camera.name ?? "",
            type: "orthographic",
            yfov: nil,
            znear: camera.zNear,
            zfar: zfar,
            xmag: camera.orthographic?.xMag,
            ymag: camera.orthographic?.yMag
        )
    }

    static func makeAnimation(_ animation: GLTFAnimation) -> GLTFSessionDocument.Animation {
        var maxTime: Float = 0
        for sampler in animation.samplers {
            if let hi = sampler.input.maxValues.first?.floatValue {
                maxTime = max(maxTime, hi)
            }
        }
        return GLTFSessionDocument.Animation(
            name: animation.name ?? "",
            duration: Double(maxTime)
        )
    }
}
