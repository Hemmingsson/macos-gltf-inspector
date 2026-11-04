import Foundation
import GLTFCore
import simd

/// Thin `SceneModel` snapshot of the open document, built from the file's JSON summary. Rebuild
/// when async validation resolves.
struct EngineSceneModel {
    var fileName: String
    var scenes: [SceneInfo]
    var defaultSceneID: NodeID?
    var nodeTree: [SceneNode]
    var lights: [LightInfo]
    var materials: [MaterialInfo]
    var animations: [AnimationInfo]
    var skins: [SkinInfo]
    var morphs: [MorphInfo]
    var materialVariantNames: [String]
    var dimensions: Dimensions
    var validation: ValidationResult
    /// Kept so a validation report that lands later can resolve its pointers to outliner rows.
    let document: GLTFSessionDocument

    /// Pass `validation: nil` while the Khronos run is pending.
    init(summary: GLTFDocumentSummary, fileName: String, validation: GLTFValidationState? = nil) {
        self.init(
            fileName: fileName,
            document: summary.document,
            dimensions: Self.mapDimensions(summary.bounds),
            validation: validation,
            materialVariantNames: summary.materialVariantNames
        )
    }

    init(
        fileName: String,
        document: GLTFSessionDocument,
        dimensions: Dimensions,
        validation: GLTFValidationState? = nil,
        materialVariantNames: [String] = []
    ) {
        let displayName = fileName.isEmpty ? "Model" : fileName
        self.fileName = displayName
        self.materialVariantNames = materialVariantNames
        self.document = document
        self.validation = Self.mapValidation(validation, document: document)

        let scenes = Self.mapScenes(document)
        self.scenes = scenes
        if document.scenes.indices.contains(document.defaultSceneIndex) {
            self.defaultSceneID = NodeID(kind: .scene, index: document.defaultSceneIndex)
        } else {
            self.defaultSceneID = scenes.first?.id
        }

        self.nodeTree = Self.buildNodeTree(document: document)
        self.lights = Self.mapLights(document.lights)
        self.materials = Self.mapMaterials(document: document)
        self.animations = Self.mapAnimations(document.animations)
        self.skins = Self.mapSkins(document.skins)
        self.morphs = Self.mapMorphs(document.morphs)
        self.dimensions = dimensions
    }

    /// Re-snapshot with a resolved validation outcome (same document / dimensions).
    func replacingValidation(_ state: GLTFValidationState?) -> EngineSceneModel {
        var copy = self
        copy.validation = Self.mapValidation(state, document: document)
        return copy
    }
}

// MARK: - Mapping

extension EngineSceneModel {
    static func mapValidation(
        _ state: GLTFValidationState?,
        document: GLTFSessionDocument
    ) -> ValidationResult {
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
                        pointer: message.pointer,
                        subjects: GLTFIssueResolver
                            .subjects(forPointer: message.pointer, in: document)
                            .compactMap { nodeID(for: $0, in: document) }
                    )
                },
                status: .ready
            )
        case .failed(let message), .skipped(let message):
            return ValidationResult(
                issues: [
                    ValidationResult.Issue(severity: .warning, message: message)
                ],
                status: .unavailable
            )
        }
    }

    /// The outliner row a validator subject is drawn on. Nil when the row does not exist.
    private static func nodeID(for subject: GLTFIssueSubject, in document: GLTFSessionDocument) -> NodeID? {
        switch subject {
        case .node(let index):
            document.nodes.first { $0.index == index }
                .map { NodeID(kind: nodeKind($0.kind), index: index) }
        case .material(let index): NodeID(kind: .material, index: index)
        case .scene(let index): NodeID(kind: .scene, index: index)
        case .skin(let index): NodeID(kind: .skin, index: index)
        case .animation(let index): NodeID(kind: .animation, index: index)
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
        displayName(scene.name, fallback: "Scene \(index)")
    }

    private static func buildNodeTree(document: GLTFSessionDocument) -> [SceneNode] {
        let byIndex = Dictionary(uniqueKeysWithValues: document.nodes.map { ($0.index, $0) })
        var seenRoots = Set<Int>()
        var roots: [SceneNode] = []

        func build(_ index: Int, path: Set<Int>) -> SceneNode? {
            guard let node = byIndex[index] else { return nil }
            var nextPath = path
            nextPath.insert(index)
            return SceneNode(
                kind: nodeKind(node.kind),
                index: node.index,
                name: displayName(node.name, fallback: "Node \(node.index)"),
                children: path.contains(index) ? [] : node.children.compactMap { build($0, path: nextPath) }
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

    /// Single camera from the document cameras array (outliner / inspector).
    static func cameraInfo(index: Int, document: GLTFSessionDocument) -> CameraInfo? {
        guard document.cameras.indices.contains(index) else { return nil }
        let camera = document.cameras[index]
        return CameraInfo(
            index: index,
            name: displayName(camera.name, fallback: "Camera \(index)"),
            isOrthographic: camera.type.lowercased() == "orthographic",
            fieldOfViewDegrees: camera.yfov.map { Double(radiansToDegrees($0)) },
            xMag: camera.xmag.map(Double.init),
            yMag: camera.ymag.map(Double.init),
            zNear: Double(camera.znear),
            zFar: camera.zfar.map(Double.init)
        )
    }

    private static func mapLights(_ lights: [GLTFSessionDocument.Light]) -> [LightInfo] {
        lights.enumerated().map { index, light in lightInfo(light, index: index) }
    }

    private static func lightInfo(_ light: GLTFSessionDocument.Light, index: Int) -> LightInfo {
        LightInfo(
            index: index,
            name: displayName(light.name, fallback: "Light \(index)"),
            kind: mapLightKind(light.type),
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

    /// Unnamed clips are numbered from 1.
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
        morphs.enumerated().map { index, morph in morphInfo(morph, index: index) }
    }

    static func morphInfo(_ morph: GLTFSessionDocument.Morph, index: Int) -> MorphInfo {
        MorphInfo(
            index: index,
            meshName: displayName(morph.meshName, fallback: "Mesh \(morph.meshIndex)"),
            targetNames: morph.targetNames
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

    static func displayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func radiansToDegrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }
}

// MARK: - Inspector detail

extension EngineSceneModel {
    /// Everything the inspector shows for one outliner row; nil when the row does not exist.
    func detail(for id: NodeID) -> NodeDetail? {
        Self.detail(for: id, document: document)
    }

    static func detail(for id: NodeID, document: GLTFSessionDocument) -> NodeDetail? {
        switch id.kind {
        // Camera and light rows are scene-tree nodes, like meshes.
        case .mesh, .empty, .camera, .light:
            guard let node = document.nodes.first(where: { $0.index == id.index }) else {
                return nil
            }
            return nodeDetail(node: node, document: document)
        case .skin:
            return skinDetail(index: id.index, document: document)
        case .material:
            return materialDetail(index: id.index, document: document)
        case .animation:
            return animationDetail(index: id.index, document: document)
        case .morph:
            return morphDetail(index: id.index, document: document)
        case .scene:
            return sceneDetail(index: id.index, document: document)
        }
    }

    private static func nodeDetail(
        node: GLTFSessionDocument.Node,
        document: GLTFSessionDocument
    ) -> NodeDetail {
        let id = NodeID(kind: Self.nodeKind(node.kind), index: node.index)
        let euler = eulerDegrees(from: node.rotation)
        let transform = TransformInfo(
            position: Vector3(
                x: Double(node.translation.x),
                y: Double(node.translation.y),
                z: Double(node.translation.z)
            ),
            rotationDegrees: Vector3(x: Double(euler.x), y: Double(euler.y), z: Double(euler.z)),
            scale: Vector3(
                x: Double(node.scale.x),
                y: Double(node.scale.y),
                z: Double(node.scale.z)
            )
        )

        let geometry: GeometryInfo? = node.kind == .mesh
            ? GeometryInfo(
                triangleCount: node.triangleCount,
                vertexCount: node.vertexCount,
                uvSetCount: node.uvSetCount,
                hasTangents: node.hasTangents,
                hasVertexColors: node.hasVertexColors
            )
            : nil

        let material: MaterialInfo? = {
            guard node.kind == .mesh,
                  let materialIndex = node.materialIndices.first,
                  document.materials.indices.contains(materialIndex)
            else { return nil }
            return Self.materialInfo(index: materialIndex, document: document)
        }()

        var camera: CameraInfo?
        var light: LightInfo?
        if node.kind == .camera, let cameraIndex = node.cameraIndex {
            camera = Self.cameraInfo(index: cameraIndex, document: document)
        }
        if node.kind == .light, let lightIndex = node.lightIndex {
            light = Self.lightInfo(index: lightIndex, document: document)
        }
        var skin: SkinInfo?
        if node.kind == .skin, let skinIndex = node.skinIndex {
            skin = Self.skinInfo(index: skinIndex, document: document)
        }

        let name = Self.displayName(node.name, fallback: "Node \(node.index)")
        return NodeDetail(
            id: id,
            name: name,
            transform: transform,
            geometry: geometry,
            material: material,
            light: light,
            camera: camera,
            skin: skin
        )
    }

    private static func materialDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.materials.indices.contains(index) else { return nil }
        let material = Self.materialInfo(index: index, document: document)
        return NodeDetail(id: material.id, name: material.name, material: material)
    }

    private static func skinDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard let skin = Self.skinInfo(index: index, document: document) else {
            return nil
        }
        return NodeDetail(id: skin.id, name: skin.name, skin: skin)
    }

    private static func animationDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.animations.indices.contains(index) else { return nil }
        let info = Self.animationInfo(document.animations[index], index: index)
        return NodeDetail(id: info.id, name: info.name, animation: info)
    }

    private static func morphDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.morphs.indices.contains(index) else { return nil }
        let info = Self.morphInfo(document.morphs[index], index: index)
        return NodeDetail(id: info.id, name: info.meshName, morph: info)
    }

    private static func sceneDetail(index: Int, document: GLTFSessionDocument) -> NodeDetail? {
        guard document.scenes.indices.contains(index) else { return nil }
        let scene = document.scenes[index]
        return NodeDetail(
            id: NodeID(kind: .scene, index: index),
            name: Self.sceneName(scene, index: index),
            sceneRootCount: scene.rootNodeIndices.count
        )
    }
}

/// Intrinsic XYZ Euler degrees from a unit quaternion (matches glTF TRS authoring).
private func eulerDegrees(from q: simd_quatf) -> SIMD3<Float> {
    let x = q.imag.x
    let y = q.imag.y
    let z = q.imag.z
    let w = q.real

    let sinr = 2 * (w * x + y * z)
    let cosr = 1 - 2 * (x * x + y * y)
    let roll = atan2(sinr, cosr)

    let sinp = 2 * (w * y - z * x)
    let pitch: Float
    if abs(sinp) >= 1 {
        pitch = copysign(.pi / 2, sinp)
    } else {
        pitch = asin(sinp)
    }

    let siny = 2 * (w * z + x * y)
    let cosy = 1 - 2 * (y * y + z * z)
    let yaw = atan2(siny, cosy)

    let toDeg: Float = 180 / .pi
    return SIMD3(roll * toDeg, pitch * toDeg, yaw * toDeg)
}
