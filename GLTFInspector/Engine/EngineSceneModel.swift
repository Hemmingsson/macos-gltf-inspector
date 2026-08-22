import Foundation
import RealityKit
import simd

/// Thin `SceneModel` snapshot over convert/load outputs. Rebuild when async validation resolves.
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

    /// Build from a loaded model. Pass `validation: nil` while the Khronos run is pending;
    /// call again with `.success` / `.failed` / `.skipped` when it resolves.
    @MainActor
    init(
        loaded: EntityLoader.LoadedModel,
        fileName: String? = nil,
        validation: GLTFValidationState? = nil
    ) {
        self.init(
            fileName: fileName ?? loaded.entity.name,
            document: loaded.document,
            stats: loaded.stats,
            dimensions: Self.mapDimensions(entity: loaded.entity),
            validation: validation,
            pipelineReport: loaded.pipelineReport,
            materialVariantNames: loaded.materialVariantNames
        )
    }

    init(
        fileName: String,
        document: GLTFSessionDocument,
        stats: PreviewStats,
        dimensions: Dimensions,
        validation: GLTFValidationState? = nil,
        pipelineReport: PreparePipelineReport,
        materialVariantNames: [String] = []
    ) {
        let displayName = fileName.isEmpty ? "Model" : fileName
        self.fileName = displayName
        self.materialVariantNames = materialVariantNames
        self.pipelineReport = Self.mapPipelineReport(pipelineReport)
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
            return ValidationResult()
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
                formatLabel: "glTF 2.0"
            )
        case .failed(let message):
            return ValidationResult(
                issues: [
                    ValidationResult.Issue(severity: .info, message: message)
                ]
            )
        case .skipped(let message):
            return ValidationResult(
                issues: [
                    ValidationResult.Issue(severity: .info, message: message)
                ]
            )
        }
    }

    static func mapPipelineReport(_ report: PreparePipelineReport) -> PipelineReport {
        var entries: [PipelineReport.Entry] = report.entries.map { line in
            let kind: PipelineReport.Entry.Kind =
                line.contains("File lights") || line.contains("Studio IBL")
                ? .lighting
                : .conversion
            return PipelineReport.Entry(kind: kind, title: line)
        }
        for name in report.extensionEntries {
            entries.append(
                PipelineReport.Entry(kind: .conversion, title: name)
            )
        }
        return PipelineReport(entries: entries)
    }

    static func mapDebugChannels(_ modes: [PreviewDebugMode]) -> [DebugChannel] {
        modes.compactMap(debugChannel(from:))
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
            let name = scene.name.isEmpty ? "Scene \(index)" : scene.name
            let rooted = scene.rootNodeIndices.map { rootIndex -> NodeID in
                if let node = document.nodes.first(where: { $0.index == rootIndex }) {
                    return NodeID(kind: mapNodeKind(node.kind), index: node.index)
                }
                return NodeID(kind: .empty, index: rootIndex)
            }
            return SceneInfo(index: index, name: name, rootNodeIDs: rooted)
        }
    }

    private static func buildNodeTree(document: GLTFSessionDocument) -> [SceneNode] {
        let byIndex = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.index, $0) })
        var seenRoots = Set<Int>()
        var roots: [SceneNode] = []

        func build(_ index: Int, path: Set<Int>) -> SceneNode? {
            guard let node = byIndex[index] else { return nil }
            guard !path.contains(index) else {
                return SceneNode(
                    kind: mapNodeKind(node.kind),
                    index: node.index,
                    name: displayName(node.name, fallback: "Node \(node.index)")
                )
            }
            var nextPath = path
            nextPath.insert(index)
            let children = node.children.compactMap { build($0, path: nextPath) }
            return SceneNode(
                kind: mapNodeKind(node.kind),
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
        cameras.enumerated().map { index, camera in
            let projection: Projection =
                camera.type.lowercased() == "orthographic" ? .orthographic : .perspective
            return CameraInfo(
                index: index,
                name: displayName(camera.name, fallback: "Camera \(index)"),
                projection: projection,
                fieldOfViewDegrees: camera.yfov.map { Double(radiansToDegrees($0)) },
                zNear: Double(camera.znear),
                zFar: camera.zfar.map(Double.init)
            )
        }
    }

    private static func mapLights(_ lights: [GLTFSessionDocument.Light]) -> [LightInfo] {
        lights.enumerated().map { index, light in
            // Document cones are radians; seam `LightInfo` has no cone fields (Selection
            // adapter converts degrees for inspector). Camera FOV is converted above.
            return LightInfo(
                index: index,
                name: displayName(light.name, fallback: "Light \(index)"),
                kind: mapLightKind(light.type),
                color: RGBColor(
                    red: Double(light.color.x),
                    green: Double(light.color.y),
                    blue: Double(light.color.z)
                ),
                intensity: Double(light.intensity),
                range: light.range.map(Double.init)
            )
        }
    }

    private static func mapMaterials(document: GLTFSessionDocument) -> [MaterialInfo] {
        document.materials.enumerated().map { index, material in
            let usedBy = document.nodes.compactMap { node -> String? in
                guard node.materialIndices.contains(index) else { return nil }
                return displayName(node.name, fallback: "Node \(node.index)")
            }
            let maps = materialMaps(material.maps)
            return MaterialInfo(
                index: index,
                name: displayName(material.name, fallback: "Material \(index)"),
                workflow: mapWorkflow(material.workflow),
                alphaMode: mapAlphaMode(material.alphaMode),
                isDoubleSided: material.isDoubleSided,
                maps: maps,
                textures: maps.map { MaterialTextureInfo(map: $0) },
                metallicFactor: material.metallicFactor.map(Double.init),
                roughnessFactor: material.roughnessFactor.map(Double.init),
                alphaCutoff: material.alphaCutoff.map(Double.init),
                usedByMeshNames: usedBy
            )
        }
    }

    private static func mapAnimations(
        _ animations: [GLTFSessionDocument.Animation]
    ) -> [AnimationInfo] {
        animations.enumerated().compactMap { index, animation in
            guard animation.duration > 0 else { return nil }
            let trimmed = animation.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = trimmed.isEmpty ? "Clip \(index + 1)" : trimmed
            return AnimationInfo(index: index, name: name, duration: animation.duration)
        }
    }

    private static func mapSkins(_ skins: [GLTFSessionDocument.Skin]) -> [SkinInfo] {
        skins.enumerated().map { index, skin in
            SkinInfo(
                index: index,
                name: displayName(skin.name, fallback: "Skin \(index)"),
                jointCount: skin.jointNames.count
            )
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
            vertexCount: stats.vertexCount,
            meshCount: meshCount,
            materialCount: stats.materialCount,
            textureCount: stats.textureCount,
            maxTextureDimension: stats.maxTextureEdge,
            animationCount: stats.animationCount,
            fileSizeBytes: stats.fileSizeBytes,
            hasVertexColors: stats.hasVertexColors,
            isRigged: stats.isRigged,
            morphTargetCount: document.morphs.reduce(0) { $0 + $1.targetNames.count }
        )
    }

    @MainActor
    static func mapDimensions(entity: Entity) -> Dimensions {
        let bounds = PreviewCamera.modelBounds(of: entity, relativeTo: entity)
        let dims = ModelDimensions(bounds: bounds)
        let center = bounds.center
        // Authored glTF origin (entity local 0) relative to the visual AABB centre.
        let authored = Vector3(
            x: Double(-center.x),
            y: Double(-center.y),
            z: Double(-center.z)
        )
        return Dimensions(
            width: Double(dims?.width ?? 0),
            height: Double(dims?.height ?? 0),
            depth: Double(dims?.depth ?? 0),
            authoredOrigin: authored
        )
    }

    private static func mapNodeKind(_ kind: GLTFSessionDocument.Node.Kind) -> NodeKind {
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

    private static func debugChannel(from mode: PreviewDebugMode) -> DebugChannel? {
        switch mode {
        case .none, .wire, .vertexColors:
            return nil
        case .visualization(let visualization):
            switch visualization {
            case .baseColor: return .baseColor
            case .metallic: return .metallic
            case .roughness: return .roughness
            case .normal: return .normals
            case .tangent: return .tangents
            case .textureCoordinates: return .textureCoordinates
            case .ambientOcclusion: return .ambientOcclusion
            case .emissive: return .emissive
            case .finalAlpha: return .alpha
            case .specular: return .specular
            case .clearcoat: return .clearcoat
            case .clearcoatRoughness: return .clearcoatRoughness
            case .clearcoatNormal: return .clearcoatNormal
            default: return nil
            }
        }
    }

    private static func displayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }
}
