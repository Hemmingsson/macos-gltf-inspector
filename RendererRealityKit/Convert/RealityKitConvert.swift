// Vendored from warrenm/GLTFKit2 GLTFRealityKit.swift (MIT), macOS-only.
// Packed accessor helpers live in PackedAccessors.swift. Patched: sheen, transmission, POINTS, unnamed joints.

import AppKit
import GLTFCore
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

final class RealityKitConvert {

    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
    fileprivate let nameGenerator = UniqueNameGenerator()

    func nextUniqueName(prefix: String) -> String {
        nameGenerator.nextUniqueName(prefix: prefix)
    }

    var pathsForSkeletonIDs: [/*MeshResource.Skeleton.ID*/String : BindTarget.EntityPath] = [:]
    var skeletonIDsByJointName: [String: [/*MeshResource.Skeleton.ID*/String]] = [:]
    var skeletonTransformsByJointName : [String: Transform] = [:]
    var sourceAsset: GLTFAsset?
    /// Per-node file index and unique entity name, built once per convert (was an O(n) scan per node).
    private var nodeIndices: [ObjectIdentifier: Int] = [:]
    private var entityNames: [ObjectIdentifier: String] = [:]
    var ignoreBakedEmissive = false

    /// One converted scene and what convert lost or changed on the way.
    struct BuildResult {
        let entity: RealityKit.Entity
        let problems: ConvertProblemReport
        /// The baked-emissive policy dropped emissive on this file.
        let droppedBakedEmissive: Bool
    }

    @MainActor static func build(scene: GLTFScene, asset: GLTFAsset) throws -> BuildResult {
        try RealityKitConvert().build(scene: scene, asset: asset)
    }

    /// Nodes and meshes first, then animations in their own exception guard: GLTFKit2 can raise
    /// ObjC exceptions, and a bad clip must not take the meshes with it (this replaces the old
    /// "no visible mesh -> convert everything again without animations" pass).
    @MainActor func build(scene: GLTFScene, asset: GLTFAsset) throws -> BuildResult {
        sourceAsset = asset
        indexNodes(asset.nodes)
        ignoreBakedEmissive = PreviewEmissive.fileLooksBaked(asset.materials.map(PreviewEmissive.hint(from:)))
        if ignoreBakedEmissive {
            AppLog.info(AppLog.lighting, "ignoring achromatic emissive boost; studio IBL already lights the model")
        }
        let context = RealityKitResourceContext()
        let rootEntity = Entity()
        rootEntity.name = "glTF_\(scene.name ?? "Scene")_Root"

        try GLBTry.run {
            do {
                for node in scene.nodes {
                    rootEntity.addChild(try self.convert(node: node, context: context))
                }
            } catch {
                AppLog.error(AppLog.load, "Error when converting scene: \(error)")
            }
        }
        guard EntityLoader.modelComponentCount(in: rootEntity) > 0 else {
            throw GLTFInspectorError.make(1022, "The glTF asset has no visible mesh")
        }

        do {
            try GLBTry.run {
                for animation in asset.animations {
                    do {
                        try self.convert(animation: animation).store(in: rootEntity)
                    } catch {
                        AppLog.error(AppLog.load, "animation convert failed: \(error)")
                    }
                }
            }
        } catch {
            context.record(.droppedAnimations, severity: .warning, message: "Animations dropped: \(error.localizedDescription)")
        }
        return BuildResult(entity: rootEntity, problems: context.problems, droppedBakedEmissive: ignoreBakedEmissive)
    }

    @MainActor func convert(node gltfNode: GLTFNode, context: RealityKitResourceContext) throws -> RealityKit.Entity {
        let nodeEntity = ModelEntity()

        nodeEntity.name = entityName(of: gltfNode)
        nodeEntity.components.set(GLTFNodeIDComponent(nodeIndex: nodeIndex(of: gltfNode)))

        nodeEntity.transform = Transform(matrix: gltfNode.matrix)

        var skeleton: MeshResource.Skeleton?
        if let skin = gltfNode.skin {
            if let meshSkeleton = convert(skin: skin) {
                skeleton = meshSkeleton
                pathsForSkeletonIDs[meshSkeleton.id] = bindPath(of: gltfNode)
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
            if let instances = instanceTransforms(gltfNode) {
                // EXT_mesh_gpu_instancing: one child per instance sharing the mesh and materials.
                // Instances are not document nodes (no GLTFNodeIDComponent), so they follow the
                // node's hide/solo and selection.
                for (index, transform) in instances.enumerated() {
                    let instance = ModelEntity()
                    instance.name = "\(nodeEntity.name)#instance\(index)"
                    instance.transform = transform
                    instance.components.set(meshComponent)
                    attachMorphWeights(to: instance, mesh: gltfMesh, node: gltfNode)
                    nodeEntity.addChild(instance)
                }
            } else {
                nodeEntity.components.set(meshComponent)
                attachMorphWeights(to: nodeEntity, mesh: gltfMesh, node: gltfNode)
            }
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

    private func attachMorphWeights(to entity: Entity, mesh: GLTFMesh, node: GLTFNode) {
        guard mesh.primitives.contains(where: { !$0.targets.isEmpty }) else { return }
        guard let model = entity.components[ModelComponent.self] else { return }
        var weights = BlendShapeWeightsComponent(
            weightsMapping: BlendShapeWeightsMapping(meshResource: model.mesh)
        )
        let initial = (node.weights ?? mesh.weights ?? []).map(\.floatValue)
        if !initial.isEmpty, !weights.weightSet.isEmpty {
            var data = weights.weightSet[0]
            data.weights = BlendShapeWeights(initial)
            weights.weightSet[0] = data
        }
        entity.components.set(weights)
    }

    /// Per-instance TRS from `EXT_mesh_gpu_instancing` (missing attributes default to identity);
    /// `nil` when the node is not instanced or the data is unusable.
    private func instanceTransforms(_ node: GLTFNode) -> [Transform]? {
        guard let attributes = node.meshInstances?.attributes, !attributes.isEmpty else { return nil }
        func accessor(_ name: String) -> GLTFAccessor? { attributes.first { $0.name == name }?.accessor }
        let translations = accessor("TRANSLATION").flatMap(Packed.float3Array(for:)) ?? []
        let rotations = accessor("ROTATION").flatMap(Packed.quatfArray(for:)) ?? []
        let scales = accessor("SCALE").flatMap(Packed.float3Array(for:)) ?? []
        let count = max(translations.count, rotations.count, scales.count)
        guard count > 0 else { return nil }
        return (0..<count).map { index in
            Transform(
                scale: index < scales.count ? scales[index] : [1, 1, 1],
                rotation: index < rotations.count ? rotations[index] : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                translation: index < translations.count ? translations[index] : .zero
            )
        }
    }

    func nodeIndex(of gltfNode: GLTFNode) -> Int {
        nodeIndices[ObjectIdentifier(gltfNode)] ?? 0
    }

    /// Entity names must be unique for animation bind paths to resolve: GLTFKit2 names unnamed
    /// nodes `NodeN`, and a repeated name gets `#<node index>`. The file's own name stays in the
    /// document (`GLTFNodeIDComponent` → node index).
    private func indexNodes(_ nodes: [GLTFNode]) {
        var used = Set<String>()
        for (index, node) in nodes.enumerated() {
            let id = ObjectIdentifier(node)
            nodeIndices[id] = index
            var name = node.name ?? ""
            if name.isEmpty || used.contains(name) {
                name = "\(name.isEmpty ? "Node" : name)#\(index)"
            }
            used.insert(name)
            entityNames[id] = name
        }
    }

    func entityName(of node: GLTFNode) -> String {
        entityNames[ObjectIdentifier(node)] ?? node.name ?? ""
    }

    /// Path from the scene root to `node`'s entity, by the same names convert gave the entities.
    func bindPath(of node: GLTFNode) -> BindTarget.EntityPath {
        if let parent = node.parent {
            return bindPath(of: parent).entity(entityName(of: node))
        }
        return BindTarget.entity(entityName(of: node))
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
            intensity: RealityLook.spotIntensity(candela: gltfLight.intensity),
            innerAngleInDegrees: RealityLook.spotConeDegrees(halfAngleRadians: gltfLight.innerConeAngle),
            outerAngleInDegrees: RealityLook.spotConeDegrees(halfAngleRadians: gltfLight.outerConeAngle),
            attenuationRadius: punctualAttenuationRadius(gltfLight.range)
        )
    }

    func convert(pointLight gltfLight: GLTFLight) -> PointLightComponent {
        PointLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: RealityLook.pointIntensity(candela: gltfLight.intensity),
            attenuationRadius: punctualAttenuationRadius(gltfLight.range)
        )
    }

    func convert(directionalLight gltfLight: GLTFLight) -> DirectionalLightComponent {
        DirectionalLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: RealityLook.directionalIntensity(lux: gltfLight.intensity),
            isRealWorldProxy: false
        )
    }

    /// glTF `range <= 0` means infinite; RealityKit rejects a zero radius.
    private func punctualAttenuationRadius(_ range: Float) -> Float {
        range > 0 ? range : 1_000_000
    }

}
