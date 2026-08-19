// Vendored from warrenm/GLTFKit2 GLTFRealityKit.swift (MIT), macOS-only.
// Packed accessor helpers live in GLBPackedAccessors.swift. Patched: sheen, transmission, POINTS, unnamed joints.

import AppKit
import RealityKit
import GLTFKit2
import simd

typealias PlatformColor = NSColor

fileprivate class UniqueNameGenerator {
    private var countsForPrefixes = [String : Int]()

    func nextUniqueName(prefix: String) -> String {
        if let existingCount = countsForPrefixes[prefix] {
            countsForPrefixes[prefix] = existingCount + 1
            return "\(prefix)\(existingCount + 1)"
        } else {
            countsForPrefixes[prefix] = 1
            return "\(prefix)1"
        }
    }
}

extension GLTFNode {
    var bindPath: BindTarget.EntityPath {
        if let parent = self.parent {
            return parent.bindPath.entity(self.name ?? "")
        }
        return BindTarget.entity(self.name ?? "")
    }
}

public class GLBRealityKitConvert {

    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
    fileprivate let nameGenerator = UniqueNameGenerator()

    func nextUniqueName(prefix: String) -> String {
        nameGenerator.nextUniqueName(prefix: prefix)
    }

    var pathsForSkeletonIDs: [/*MeshResource.Skeleton.ID*/String : BindTarget.EntityPath] = [:]
    var skeletonIDsByJointName: [String: [/*MeshResource.Skeleton.ID*/String]] = [:]
    var skeletonTransformsByJointName : [String: Transform] = [:]
    var sourceAsset: GLTFAsset?
    var ignoreBakedEmissive = false

    @MainActor static func convert(
        scene: GLTFScene,
        asset: GLTFAsset?,
        document: inout GLTFSessionDocument
    ) -> RealityKit.Entity {
        let instance = GLBRealityKitConvert()
        return instance.convert(scene: scene, asset: asset, document: &document)
    }

    @MainActor func convert(
        scene: GLTFScene,
        asset: GLTFAsset? = nil,
        document: inout GLTFSessionDocument
    ) -> RealityKit.Entity {
        sourceAsset = asset
        if let asset {
            document = Self.makeDocument(from: asset)
        }
        let emissiveHints = (asset?.materials ?? []).map(GLBPreviewEmissive.hint(from:))
        ignoreBakedEmissive = GLBPreviewEmissive.fileLooksBaked(emissiveHints)
        if ignoreBakedEmissive {
            GLBLog.info(GLBLog.lighting, "ignoring achromatic emissive boost; studio IBL already lights the model")
        }
        let context = GLBRealityKitResourceContext()

        let rootEntity = Entity()
        rootEntity.name = "glTF_\(scene.name ?? "Scene")_Root"

        do {
            let rootNodes = try scene.nodes.compactMap { try self.convert(node: $0, context: context) }

            for rootNode in rootNodes {
                rootEntity.addChild(rootNode)
            }
        } catch {
            GLBLog.error(GLBLog.load, "Error when converting scene: \(error)")
        }

        // TODO: Morph targets

        for animation in asset?.animations ?? [] {
            let rkAnimation = try? convert(animation: animation)
            rkAnimation?.store(in: rootEntity)
        }

        return rootEntity
    }

    @MainActor func convert(node gltfNode: GLTFNode, context: GLBRealityKitResourceContext) throws -> RealityKit.Entity {
        let nodeEntity = ModelEntity()

        // TODO: This only ensures uniqueness for unnamed nodes; the asset could still contain duplicate names.
        nodeEntity.name = gltfNode.name ?? nameGenerator.nextUniqueName(prefix: "Node")
        nodeEntity.components.set(GLTFNodeIDComponent(nodeIndex: nodeIndex(of: gltfNode)))

        nodeEntity.transform = Transform(matrix: gltfNode.matrix)

        var skeleton: Any?
        if let skin = gltfNode.skin {
            if let meshSkeleton = convert(skin: skin) {
                skeleton = meshSkeleton
                pathsForSkeletonIDs[meshSkeleton.id] = gltfNode.bindPath
                for joint in meshSkeleton.joints {
                    if joint.parentIndex == nil, let referenceNode = skin.skeleton {
                        skeletonTransformsByJointName[joint.name] = Transform(matrix: referenceNode.matrix)
                    }
                    if let existingJointCache = skeletonIDsByJointName[joint.name] {
                        skeletonIDsByJointName[joint.name] = existingJointCache + [meshSkeleton.id]
                    } else {
                        skeletonIDsByJointName[joint.name] = [meshSkeleton.id]
                    }
                }
            }
        }

        if let gltfMesh = gltfNode.mesh,
           let meshComponent = try convert(mesh: gltfMesh, skeleton: skeleton, context: context) {
            nodeEntity.components.set(meshComponent)
        }

        if let gltfLight = gltfNode.light {
            switch gltfLight.type {
            case .directional:
                nodeEntity.components.set(convert(directionalLight: gltfLight))
            case .point:
                nodeEntity.components.set(convert(pointLight: gltfLight))
            case .spot:
                nodeEntity.components.set(convert(spotLight: gltfLight))
            default:
                break
            }
        }

        if let gltfCamera = gltfNode.camera, let cameraComponent = convert(camera: gltfCamera) {
            nodeEntity.components.set(cameraComponent)
        }

        for childNode in gltfNode.childNodes {
            nodeEntity.addChild(try convert(node: childNode, context: context))
        }

        return nodeEntity
    }

    func nodeIndex(of gltfNode: GLTFNode) -> Int {
        guard let nodes = sourceAsset?.nodes else { return 0 }
        return nodes.firstIndex(where: { $0 === gltfNode }) ?? 0
    }

    func platformColor(for vector: simd_float4) -> PlatformColor {
        let components = [CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z), CGFloat(vector.w)]
        return NSColor(colorSpace: colorSpace, components: components, count: components.count)
    }

    func convert(camera: GLTFCamera) -> (any Component)? {
        if let perspectiveParams = camera.perspective {
            return PerspectiveCameraComponent(
                near: camera.zNear,
                far: camera.zFar,
                fieldOfViewInDegrees: GLTFDegFromRad(perspectiveParams.yFOV)
            )
        }
        if let orthographicParams = camera.orthographic {
            var orthographic = OrthographicCameraComponent()
            orthographic.near = camera.zNear
            orthographic.far = camera.zFar
            orthographic.scale = orthographicParams.yMag
            return orthographic
        }
        return nil
    }

    func convert(spotLight gltfLight: GLTFLight) -> SpotLightComponent {
        SpotLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: gltfLight.intensity * 4 * .pi,
            innerAngleInDegrees: GLTFDegFromRad(gltfLight.innerConeAngle),
            outerAngleInDegrees: GLTFDegFromRad(gltfLight.outerConeAngle),
            attenuationRadius: punctualAttenuationRadius(gltfLight.range)
        )
    }

    func convert(pointLight gltfLight: GLTFLight) -> PointLightComponent {
        PointLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: gltfLight.intensity * 4 * .pi,
            attenuationRadius: punctualAttenuationRadius(gltfLight.range)
        )
    }

    func convert(directionalLight gltfLight: GLTFLight) -> DirectionalLightComponent {
        DirectionalLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: gltfLight.intensity,
            isRealWorldProxy: false
        )
    }

    /// glTF `range <= 0` means infinite; RealityKit rejects a zero radius.
    private func punctualAttenuationRadius(_ range: Float) -> Float {
        range > 0 ? range : 1_000_000
    }

}
