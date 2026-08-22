import CoreGraphics
import Foundation
import GLTFKit2
import ImageIO
import UniformTypeIdentifiers

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
        let geometryByMesh = Dictionary(
            uniqueKeysWithValues: asset.meshes.enumerated().map { ($0.offset, meshGeometry($0.element)) }
        )
        document.nodes = asset.nodes.enumerated().map { index, node in
            makeNode(
                node,
                index: index,
                asset: asset,
                materialIndicesByMesh: materialIndicesLookup,
                geometryByMesh: geometryByMesh
            )
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

    /// Fill material texture pixel size + PNG thumbs from the convert context's decoded images.
    @MainActor
    static func stampMaterialPreviews(
        document: inout GLTFSessionDocument,
        asset: GLTFAsset,
        context: RealityKitResourceContext
    ) {
        guard document.materials.count == asset.materials.count else { return }
        var thumbCache = [UUID: Data]()
        for index in document.materials.indices {
            let gltf = asset.materials[index]
            var slots = document.materials[index].textures
            for slotIndex in slots.indices {
                guard let params = textureParams(for: slots[slotIndex].kind, on: gltf),
                      let image = RealityKitResourceContext.gltfImage(for: params.texture)
                else { continue }
                if let cgImage = context.cgImage(for: image) {
                    slots[slotIndex].width = cgImage.width
                    slots[slotIndex].height = cgImage.height
                    if let cached = thumbCache[image.identifier] {
                        slots[slotIndex].thumbnailPNG = cached
                    } else if let png = thumbnailPNG(from: cgImage, maxEdge: 96) {
                        thumbCache[image.identifier] = png
                        slots[slotIndex].thumbnailPNG = png
                    }
                }
            }
            document.materials[index].textures = slots
        }
    }

    static func makeNode(
        _ node: GLTFNode,
        index: Int,
        asset: GLTFAsset,
        materialIndicesByMesh: [Int: [Int]] = [:],
        geometryByMesh: [Int: MeshGeometryStamp] = [:]
    ) -> GLTFSessionDocument.Node {
        let meshIndex = identityIndex(node.mesh, in: asset.meshes)
        let cameraIndex = identityIndex(node.camera, in: asset.cameras)
        let lightIndex = identityIndex(node.light, in: asset.lights)
        let skinIndex = identityIndex(node.skin, in: asset.skins)
        let materialIndices = meshIndex.flatMap { materialIndicesByMesh[$0] } ?? []
        let geometry = meshIndex.flatMap { geometryByMesh[$0] }
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
            materialIndices: materialIndices,
            triangleCount: geometry?.triangleCount ?? 0,
            vertexCount: geometry?.vertexCount ?? 0,
            uvSetCount: geometry?.uvSetCount ?? 0,
            hasNormals: geometry?.hasNormals ?? false,
            hasTangents: geometry?.hasTangents ?? false,
            hasVertexColors: geometry?.hasVertexColors ?? false
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

    struct MeshGeometryStamp {
        var triangleCount = 0
        var vertexCount = 0
        var uvSetCount = 0
        var hasNormals = false
        var hasTangents = false
        var hasVertexColors = false
    }

    private static func meshGeometry(_ mesh: GLTFMesh) -> MeshGeometryStamp {
        var stamp = MeshGeometryStamp()
        var maxUV = 0
        for primitive in mesh.primitives {
            let positions = primitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            stamp.vertexCount += positions
            if primitive.attribute(forName: "NORMAL") != nil { stamp.hasNormals = true }
            if primitive.attribute(forName: "TANGENT") != nil { stamp.hasTangents = true }
            if primitive.attribute(forName: "COLOR_0") != nil { stamp.hasVertexColors = true }
            for uv in 0..<8 {
                if primitive.attribute(forName: "TEXCOORD_\(uv)") != nil {
                    maxUV = max(maxUV, uv + 1)
                }
            }
            let count: Int
            if let indices = primitive.indices {
                count = indices.count
            } else {
                count = positions
            }
            switch primitive.primitiveType {
            case .triangles:
                stamp.triangleCount += count / 3
            case .triangleStrip, .triangleFan:
                stamp.triangleCount += max(0, count - 2)
            default:
                break
            }
        }
        stamp.uvSetCount = maxUV
        return stamp
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
        let slots = textureSlots(from: material)
        return GLTFSessionDocument.Material(
            name: material.name ?? "",
            maps: MaterialMapPresence.from(gltf: material),
            workflow: workflow,
            alphaMode: alphaMode,
            isDoubleSided: material.isDoubleSided,
            metallicFactor: metallic?.metallicFactor,
            roughnessFactor: metallic?.roughnessFactor,
            alphaCutoff: alphaMode == .mask ? material.alphaCutoff : nil,
            baseColorFactor: metallic?.baseColorFactor,
            emissiveFactor: material.emissive?.emissiveFactor,
            normalScale: material.normalTexture?.scale,
            occlusionStrength: material.occlusionTexture?.scale,
            textures: slots
        )
    }

    private static func textureSlots(from material: GLTFMaterial) -> [GLTFSessionDocument.TextureSlot] {
        var slots: [GLTFSessionDocument.TextureSlot] = []
        func append(_ kind: GLTFSessionDocument.TextureSlot.Kind, _ params: GLTFTextureParams?) {
            guard let params else { return }
            slots.append(.init(kind: kind, texCoord: Int(params.texCoord)))
        }
        append(.baseColor, material.metallicRoughness?.baseColorTexture
            ?? material.specularGlossiness?.diffuseTexture)
        append(.metallicRoughness, material.metallicRoughness?.metallicRoughnessTexture)
        append(.normal, material.normalTexture)
        append(.occlusion, material.occlusionTexture)
        append(.emissive, material.emissive?.emissiveTexture)
        append(.specular, material.specular?.specularTexture
            ?? material.specular?.specularColorTexture
            ?? material.specularGlossiness?.specularGlossinessTexture)
        if let clearcoat = material.clearcoat {
            append(.clearcoat, clearcoat.clearcoatTexture)
            append(.clearcoatRoughness, clearcoat.clearcoatRoughnessTexture)
            append(.clearcoatNormal, clearcoat.clearcoatNormalTexture)
        }
        return slots
    }

    private static func textureParams(
        for kind: GLTFSessionDocument.TextureSlot.Kind,
        on material: GLTFMaterial
    ) -> GLTFTextureParams? {
        switch kind {
        case .baseColor:
            return material.metallicRoughness?.baseColorTexture
                ?? material.specularGlossiness?.diffuseTexture
        case .metallicRoughness:
            return material.metallicRoughness?.metallicRoughnessTexture
        case .normal:
            return material.normalTexture
        case .occlusion:
            return material.occlusionTexture
        case .emissive:
            return material.emissive?.emissiveTexture
        case .specular:
            return material.specular?.specularTexture
                ?? material.specular?.specularColorTexture
                ?? material.specularGlossiness?.specularGlossinessTexture
        case .clearcoat:
            return material.clearcoat?.clearcoatTexture
        case .clearcoatRoughness:
            return material.clearcoat?.clearcoatRoughnessTexture
        case .clearcoatNormal:
            return material.clearcoat?.clearcoatNormalTexture
        }
    }

    private static func thumbnailPNG(from image: CGImage, maxEdge: Int) -> Data? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let longest = max(width, height)
        let scale = longest > maxEdge ? CGFloat(maxEdge) / CGFloat(longest) : 1
        let outW = max(1, Int((CGFloat(width) * scale).rounded()))
        let outH = max(1, Int((CGFloat(height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: outW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let scaled = ctx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, scaled, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
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
