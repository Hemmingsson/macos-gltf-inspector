import Foundation
import GLTFCore
import PreviewUI
import simd

/// Thin `SceneModel` snapshot of the open document. Built from the JSON summary (WebKit window) or
/// from the RealityKit load (`RealityKit/EngineSceneModel+RealityKit.swift`). Rebuild when async
/// validation resolves.
struct EngineSceneModel: SceneModel {
    var fileName: String
    var scenes: [SceneInfo]
    var defaultSceneID: NodeID?
    var nodeTree: [SceneNode]
    var cameras: [CameraInfo]
    var lights: [LightInfo]
    var materials: [MaterialInfo]
    var animations: [AnimationInfo]
    var skins: [SkinInfo]
    var morphs: [MorphInfo]
    var materialVariantNames: [String]
    var stats: Stats
    var dimensions: Dimensions
    var validation: ValidationResult
    var pipelineReport: PipelineReport
    var convertProblems: ConvertProblemList

    /// Build from the file's JSON alone. Pass `validation: nil` while the Khronos run is pending.
    /// No convert ran, so there is no pipeline or convert-problem report.
    init(summary: GLTFDocumentSummary, fileName: String, validation: GLTFValidationState? = nil) {
        self.init(
            fileName: fileName,
            document: summary.document,
            stats: summary.stats,
            dimensions: Self.mapDimensions(summary.bounds),
            validation: validation,
            materialVariantNames: summary.materialVariantNames
        )
    }

    init(
        fileName: String,
        document: GLTFSessionDocument,
        stats: PreviewStats,
        dimensions: Dimensions,
        validation: GLTFValidationState? = nil,
        pipelineReport: PipelineReport = PipelineReport(),
        convertProblems: ConvertProblemList = ConvertProblemList(),
        materialVariantNames: [String] = []
    ) {
        let displayName = fileName.isEmpty ? "Model" : fileName
        self.fileName = displayName
        self.materialVariantNames = materialVariantNames
        self.pipelineReport = pipelineReport
        self.convertProblems = convertProblems
        self.validation = Self.mapValidation(validation)

        let scenes = Self.mapScenes(document)
        self.scenes = scenes
        if document.scenes.indices.contains(document.defaultSceneIndex) {
            self.defaultSceneID = NodeID(kind: .scene, index: document.defaultSceneIndex)
        } else {
            self.defaultSceneID = scenes.first?.id
        }

        self.nodeTree = Self.buildNodeTree(document: document)
        self.cameras = Self.mapCameras(document.cameras)
        self.lights = Self.mapLights(document.lights)
        self.materials = Self.mapMaterials(document: document)
        self.animations = Self.mapAnimations(document.animations)
        self.skins = Self.mapSkins(document.skins)
        self.morphs = Self.mapMorphs(document.morphs)
        self.stats = Self.mapStats(stats, document: document)
        self.dimensions = dimensions
    }

    /// Re-snapshot with a resolved validation outcome (same document / stats / dimensions).
    func replacingValidation(_ state: GLTFValidationState?) -> EngineSceneModel {
        var copy = self
        copy.validation = Self.mapValidation(state)
        return copy
    }
}

// MARK: - Mapping

extension EngineSceneModel {
    static func mapValidation(_ state: GLTFValidationState?) -> ValidationResult {
        guard let state else {
            return ValidationResult(status: .pending)
        }
        switch state {
        case .success(let report):
            return ValidationResult(
                issues: report.messages.map { message in
                    ValidationResult.Issue(
                        severity: mapSeverity(message.severity),
                        message: message.message,
                        pointer: message.pointer
                    )
                },
                formatLabel: "glTF 2.0",
                status: .ready
            )
        case .failed(let message):
            return ValidationResult(
                issues: [
                    ValidationResult.Issue(severity: .warning, message: message)
                ],
                status: .unavailable
            )
        case .skipped(let message):
            return ValidationResult(
                issues: [
                    ValidationResult.Issue(severity: .warning, message: message)
                ],
                status: .unavailable
            )
        }
    }

    static func mapDebugChannels(_ modes: [RenderViewMode]) -> [DebugChannel] {
        var seen = Set<DebugChannel>()
        return modes.compactMap { mode in
            guard case .channel(let channel) = mode else { return nil }
            let mapped = DebugChannel(channel)
            return seen.insert(mapped).inserted ? mapped : nil
        }
    }

    private static func mapSeverity(_ severity: Int) -> ValidationResult.Issue.Severity {
        switch severity {
        case 0: .error
        case 1: .warning
        case 2: .info
        default: .hint
        }
    }

    private static func mapScenes(_ document: GLTFSessionDocument) -> [SceneInfo] {
        document.scenes.enumerated().map { index, scene in
            SceneInfo(index: index, name: sceneName(scene, index: index))
        }
    }

    static func sceneName(_ scene: GLTFSessionDocument.Scene, index: Int) -> String {
        scene.name.isEmpty ? "Scene \(index)" : scene.name
    }

    private static func buildNodeTree(document: GLTFSessionDocument) -> [SceneNode] {
        let byIndex = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.index, $0) })
        var seenRoots = Set<Int>()
        var roots: [SceneNode] = []

        func build(_ index: Int, path: Set<Int>) -> SceneNode? {
            guard let node = byIndex[index] else { return nil }
            guard !path.contains(index) else {
                return SceneNode(
                    kind: nodeKind(node.kind),
                    index: node.index,
                    name: displayName(node.name, fallback: "Node \(node.index)")
                )
            }
            var nextPath = path
            nextPath.insert(index)
            let children = node.children.compactMap { build($0, path: nextPath) }
            return SceneNode(
                kind: nodeKind(node.kind),
                index: node.index,
                name: displayName(node.name, fallback: "Node \(node.index)"),
                children: children
            )
        }

        for scene in document.scenes {
            for rootIndex in scene.rootNodeIndices where !seenRoots.contains(rootIndex) {
                guard let root = build(rootIndex, path: []) else { continue }
                seenRoots.insert(rootIndex)
                roots.append(root)
            }
        }

        if roots.isEmpty {
            let childSet = Set(document.nodes.flatMap(\.children))
            for node in document.nodes where !childSet.contains(node.index) {
                guard !seenRoots.contains(node.index), let root = build(node.index, path: []) else {
                    continue
                }
                seenRoots.insert(node.index)
                roots.append(root)
            }
        }

        return roots
    }

    private static func mapCameras(_ cameras: [GLTFSessionDocument.Camera]) -> [CameraInfo] {
        cameras.enumerated().map { index, camera in cameraInfo(camera, index: index) }
    }

    private static func cameraInfo(_ camera: GLTFSessionDocument.Camera, index: Int) -> CameraInfo {
        let projection: Projection =
            camera.type.lowercased() == "orthographic" ? .orthographic : .perspective
        return CameraInfo(
            index: index,
            name: displayName(camera.name, fallback: "Camera \(index)"),
            projection: projection,
            fieldOfViewDegrees: camera.yfov.map { Double(radiansToDegrees($0)) },
            xMag: camera.xmag.map(Double.init),
            yMag: camera.ymag.map(Double.init),
            zNear: Double(camera.znear),
            zFar: camera.zfar.map(Double.init)
        )
    }

    /// Single camera from the document cameras array (outliner / inspector).
    static func cameraInfo(index: Int, document: GLTFSessionDocument) -> CameraInfo? {
        guard document.cameras.indices.contains(index) else { return nil }
        return cameraInfo(document.cameras[index], index: index)
    }

    private static func mapLights(_ lights: [GLTFSessionDocument.Light]) -> [LightInfo] {
        lights.enumerated().map { index, light in lightInfo(light, index: index) }
    }

    private static func lightInfo(_ light: GLTFSessionDocument.Light, index: Int) -> LightInfo {
        LightInfo(
            index: index,
            name: displayName(light.name, fallback: "Light \(index)"),
            kind: mapLightKind(light.type),
            color: RGBColor(
                red: Double(light.color.x),
                green: Double(light.color.y),
                blue: Double(light.color.z)
            ),
            intensity: Double(light.intensity),
            range: light.range.map(Double.init),
            innerConeDegrees: light.innerCone.map { Double(radiansToDegrees($0)) },
            outerConeDegrees: light.outerCone.map { Double(radiansToDegrees($0)) }
        )
    }

    static func lightInfo(index: Int, document: GLTFSessionDocument) -> LightInfo? {
        guard document.lights.indices.contains(index) else { return nil }
        return lightInfo(document.lights[index], index: index)
    }

    private static func mapMaterials(document: GLTFSessionDocument) -> [MaterialInfo] {
        document.materials.indices.map { materialInfo(index: $0, document: document) }
    }

    static func materialInfo(index: Int, document: GLTFSessionDocument) -> MaterialInfo {
        let material = document.materials[index]
        let usedBy = document.nodes.compactMap { node -> String? in
            guard node.materialIndices.contains(index) else { return nil }
            return displayName(node.name, fallback: "Node \(node.index)")
        }
        let textures = material.textures.map { slot in
            MaterialTextureInfo(
                map: materialMap(slot.kind),
                width: slot.width,
                height: slot.height,
                texCoord: slot.texCoord,
                thumbnailPNG: slot.thumbnailPNG
            )
        }
        return MaterialInfo(
            index: index,
            name: displayName(material.name, fallback: "Material \(index)"),
            workflow: mapWorkflow(material.workflow),
            alphaMode: mapAlphaMode(material.alphaMode),
            isDoubleSided: material.isDoubleSided,
            maps: materialMaps(material.maps),
            textures: textures,
            baseColorFactor: material.baseColorFactor.map {
                RGBColor(red: Double($0.x), green: Double($0.y), blue: Double($0.z))
            },
            metallicFactor: material.metallicFactor.map(Double.init),
            roughnessFactor: material.roughnessFactor.map(Double.init),
            emissiveFactor: material.emissiveFactor.map {
                RGBColor(red: Double($0.x), green: Double($0.y), blue: Double($0.z))
            },
            emissiveStrength: material.emissiveStrength.map(Double.init),
            normalScale: material.normalScale.map(Double.init),
            occlusionStrength: material.occlusionStrength.map(Double.init),
            alphaCutoff: material.alphaCutoff.map(Double.init),
            usedByMeshNames: usedBy
        )
    }

    private static func mapAnimations(
        _ animations: [GLTFSessionDocument.Animation]
    ) -> [AnimationInfo] {
        animations.enumerated().compactMap { index, animation in
            guard animation.duration > 0 else { return nil }
            return animationInfo(animation, index: index)
        }
    }

    /// Unnamed clips are numbered from 1, as the transport shows them.
    static func animationInfo(_ animation: GLTFSessionDocument.Animation, index: Int) -> AnimationInfo {
        AnimationInfo(
            index: index,
            name: displayName(animation.name, fallback: "Clip \(index + 1)"),
            duration: animation.duration
        )
    }

    private static func mapSkins(_ skins: [GLTFSessionDocument.Skin]) -> [SkinInfo] {
        skins.enumerated().map { index, skin in skinInfo(skin, index: index) }
    }

    private static func skinInfo(_ skin: GLTFSessionDocument.Skin, index: Int) -> SkinInfo {
        SkinInfo(
            index: index,
            name: displayName(skin.name, fallback: "Skin \(index)"),
            jointCount: skin.jointNames.count,
            jointNames: skin.jointNames
        )
    }

    static func skinInfo(index: Int, document: GLTFSessionDocument) -> SkinInfo? {
        guard document.skins.indices.contains(index) else { return nil }
        return skinInfo(document.skins[index], index: index)
    }

    private static func materialMap(_ kind: GLTFSessionDocument.TextureSlot.Kind) -> MaterialMap {
        switch kind {
        case .baseColor: .baseColor
        case .normal: .normal
        case .metallicRoughness: .metallicRoughness
        case .occlusion: .occlusion
        case .emissive: .emissive
        case .specular: .specular
        case .clearcoat: .clearcoat
        case .clearcoatRoughness: .clearcoatRoughness
        case .clearcoatNormal: .clearcoatNormal
        }
    }

    private static func mapMorphs(_ morphs: [GLTFSessionDocument.Morph]) -> [MorphInfo] {
        morphs.enumerated().map { index, morph in
            MorphInfo(
                index: index,
                meshName: displayName(morph.meshName, fallback: "Mesh \(morph.meshIndex)"),
                targetNames: morph.targetNames
            )
        }
    }

    private static func mapStats(_ stats: PreviewStats, document: GLTFSessionDocument) -> Stats {
        let meshCount = Set(document.nodes.compactMap(\.meshIndex)).count
        return Stats(
            triangleCount: stats.triangleCount,
            meshCount: meshCount,
            materialCount: stats.materialCount,
            textureCount: stats.textureCount,
            maxTextureDimension: stats.maxTextureEdge,
            animationCount: stats.animationCount,
            fileSizeBytes: stats.fileSizeBytes
        )
    }

    /// JSON bounds → seam dimensions. The authored glTF origin is reported relative to the box
    /// centre (the canvas frames the centre).
    static func mapDimensions(_ bounds: ModelBounds?) -> Dimensions {
        guard let bounds else {
            return Dimensions(width: 0, height: 0, depth: 0, authoredOrigin: .zero)
        }
        return Dimensions(
            width: Double(bounds.size.x),
            height: Double(bounds.size.y),
            depth: Double(bounds.size.z),
            authoredOrigin: Vector3(
                x: Double(-bounds.center.x),
                y: Double(-bounds.center.y),
                z: Double(-bounds.center.z)
            )
        )
    }

    static func nodeKind(_ kind: GLTFSessionDocument.Node.Kind) -> NodeKind {
        switch kind {
        case .empty: .empty
        case .mesh: .mesh
        case .camera: .camera
        case .light: .light
        case .skin: .skin
        }
    }

    private static func mapLightKind(_ type: String) -> LightInfo.Kind {
        switch type.lowercased() {
        case "directional": .directional
        case "spot": .spot
        default: .point
        }
    }

    private static func mapWorkflow(
        _ workflow: GLTFSessionDocument.Material.Workflow
    ) -> MaterialInfo.Workflow {
        switch workflow {
        case .metallicRoughness: .metallicRoughness
        case .specularGlossiness: .specularGlossiness
        case .unlit: .unlit
        }
    }

    private static func mapAlphaMode(
        _ mode: GLTFSessionDocument.Material.AlphaMode
    ) -> MaterialInfo.AlphaMode {
        switch mode {
        case .opaque: .opaque
        case .mask: .mask
        case .blend: .blend
        }
    }

    private static func materialMaps(_ presence: MaterialMapPresence) -> Set<MaterialMap> {
        var maps = Set<MaterialMap>()
        if presence.baseColor { maps.insert(.baseColor) }
        if presence.normal { maps.insert(.normal) }
        if presence.metallicRoughness { maps.insert(.metallicRoughness) }
        if presence.occlusion { maps.insert(.occlusion) }
        if presence.emissive { maps.insert(.emissive) }
        if presence.specular { maps.insert(.specular) }
        if presence.clearcoat { maps.insert(.clearcoat) }
        if presence.clearcoatRoughness { maps.insert(.clearcoatRoughness) }
        if presence.clearcoatNormal { maps.insert(.clearcoatNormal) }
        return maps
    }

    private static func displayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }
}
