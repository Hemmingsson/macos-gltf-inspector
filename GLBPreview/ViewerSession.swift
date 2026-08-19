import RealityKit
import SwiftUI
import simd

@Observable
final class ViewerSession {
    var imageBased = true
    var punctualLights = true
    var iblIntensity: Float = 1
    var environment: GLBKhronosEnvironments = .studioNeutral
    var environmentRotation: EnvironmentRotation = .plusZ
    var showEnvironmentMap = false
    var blurEnvironment = false
    var backgroundColor = Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)
    var userHDRs: [URL] = []
    var selectedUserHDR: URL?
    var inspectorError: String?
    var toneMap: ToneMap = .khronosPBRNeutral
    var exposure: Float = 1
    var hide = Set<Int>()
    var soloRoot: Int?
    var debug: DebugMode = .none
    var activeSceneIndex: Int
    /// `nil` is the Fit camera; otherwise an index into `document.cameras`.
    var selectedCameraIndex: Int?
    var selected: Selection = .none
    var frameNonce = 0
    var enabledClipIndices: Set<Int>
    var isPlaying = true
    var currentTime: TimeInterval = 0
    var clipDuration: TimeInterval = 0
    var variantIndex = 0
    let defaultExponent: Float
    let document: GLTFSessionDocument
    weak var boundRoot: Entity?
    weak var boundIBL: Entity?
    @ObservationIgnored private var playbackControllers: [AnimationPlaybackController] = []
    @ObservationIgnored private var cachedOriginalMaterials: [ObjectIdentifier: [any RealityKit.Material]] = [:]

    enum Selection: Equatable, Hashable {
        case none
        case node(Int)
        case animation(Int)
    }

    enum EnvironmentRotation: String, CaseIterable {
        case plusZ = "+Z"
        case minusX = "−X"
        case minusZ = "−Z"
        case plusX = "+X"

        var yawRadians: Float {
            switch self {
            case .plusZ: 0
            case .minusX: .pi / 2
            case .minusZ: .pi
            case .plusX: -.pi / 2
            }
        }
    }

    enum ToneMap: String, CaseIterable {
        case khronosPBRNeutral
        case acesHillExposureBoost
        case acesNarkowicz
        case acesHill
        case noneLinear

        var title: String {
            switch self {
            case .khronosPBRNeutral: "Khronos PBR Neutral"
            case .acesHillExposureBoost: "ACES Filmic Tone Mapping (Hill - Exposure Boost)"
            case .acesNarkowicz: "ACES Filmic Tone Mapping (Narkowicz)"
            case .acesHill: "ACES Filmic Tone Mapping (Hill)"
            case .noneLinear: "None (Linear mapping, clamped at 1.0)"
            }
        }
    }

    enum DebugMode: String, CaseIterable {
        case none, baseColor, roughness, metalness, normals, emission, wireframe
    }

    init(document: GLTFSessionDocument, defaultExponent: Float) {
        self.document = document
        self.defaultExponent = defaultExponent
        self.activeSceneIndex = document.defaultSceneIndex
        self.enabledClipIndices = Set(document.animations.indices)
        self.clipDuration = document.animations.map(\.duration).max() ?? 0
    }

    func layerRootIndices() -> [Int] {
        guard document.scenes.indices.contains(activeSceneIndex) else { return [] }
        return document.scenes[activeSceneIndex].rootNodeIndices
    }

    @MainActor
    func bind(root: Entity, iblEntity: Entity?) {
        let rebound = boundRoot !== root
        boundRoot = root
        boundIBL = iblEntity
        if rebound {
            cachedOriginalMaterials.removeAll()
            startPlayback()
        }
    }

    @MainActor
    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            if playbackControllers.isEmpty {
                startPlayback()
            } else {
                playbackControllers.forEach { $0.resume() }
            }
        } else {
            playbackControllers.forEach { $0.pause() }
        }
    }

    @MainActor
    func setClipEnabled(_ index: Int, enabled: Bool) {
        if enabled {
            enabledClipIndices.insert(index)
        } else {
            enabledClipIndices.remove(index)
        }
        startPlayback()
    }

    @MainActor
    func seek(to time: TimeInterval) {
        let duration = max(clipDuration, 0)
        let clamped = duration > 0 ? min(max(time, 0), duration) : 0
        currentTime = clamped
        for controller in playbackControllers {
            controller.time = clamped
        }
    }

    @MainActor
    func syncPlaybackTime() {
        guard let first = playbackControllers.first, clipDuration > 0 else { return }
        var time = first.time.truncatingRemainder(dividingBy: clipDuration)
        if time < 0 { time += clipDuration }
        currentTime = time
    }

    @MainActor
    func startPlayback() {
        guard let root = boundRoot else { return }
        stopPlayback()
        let clips = root.availableAnimations
        var maxDuration: TimeInterval = 0
        for index in enabledClipIndices.sorted() {
            guard clips.indices.contains(index) else { continue }
            let clip = clips[index]
            let controller: AnimationPlaybackController
            if isPlaying {
                controller = root.playAnimation(clip.repeat())
            } else {
                controller = root.playAnimation(clip, startsPaused: true)
            }
            let duration = controller.duration
            if duration.isFinite, duration > 0 {
                maxDuration = max(maxDuration, duration)
            }
            playbackControllers.append(controller)
        }
        if maxDuration > 0 {
            clipDuration = maxDuration
        } else {
            clipDuration = document.animations.enumerated()
                .filter { enabledClipIndices.contains($0.offset) }
                .map(\.element.duration)
                .max() ?? 0
        }
    }

    @MainActor
    private func stopPlayback() {
        playbackControllers.forEach { $0.stop() }
        playbackControllers.removeAll()
    }

    @MainActor
    func applyIfBound() {
        guard let boundRoot else { return }
        apply(root: boundRoot, iblEntity: boundIBL)
    }

    @MainActor
    func apply(root: Entity, iblEntity: Entity?) {
        if imageBased, let iblEntity {
            applyReceivers(from: iblEntity, to: root)
        } else if !imageBased {
            removeReceivers(from: root)
        }

        if let iblEntity, var light = iblEntity.components[ImageBasedLightComponent.self] {
            light.intensityExponent = intensityExponent(forSlider: iblIntensity)
            iblEntity.components.set(light)
            iblEntity.orientation = simd_quatf(
                angle: environmentRotation.yawRadians,
                axis: SIMD3<Float>(0, 1, 0)
            )
        }

        applyVisibility(to: root)
        applyVariant(to: root)
    }

    func showAll() {
        hide.removeAll()
        soloRoot = nil
    }

    func requestFrame() {
        frameNonce += 1
    }

    func entity(nodeIndex: Int, in root: Entity) -> Entity? {
        if root.components[GLTFNodeIDComponent.self]?.nodeIndex == nodeIndex {
            return root
        }
        for child in root.children {
            if let found = entity(nodeIndex: nodeIndex, in: child) {
                return found
            }
        }
        return nil
    }

    func frameTarget(in root: Entity) -> Entity {
        if case .node(let index) = selected, let match = entity(nodeIndex: index, in: root) {
            return match
        }
        return root
    }

    func soloHides(_ id: Int) -> Bool {
        guard let soloRoot else { return false }
        if id == soloRoot { return false }
        if ancestorIndices(of: soloRoot).contains(id) { return false }
        return layerRootIndices().contains(id)
    }

    func intensityExponent(forSlider value: Float) -> Float {
        defaultExponent + log2(max(value, 0.01))
    }

    @MainActor
    private func applyReceivers(from light: Entity, to entity: Entity) {
        entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
        for child in entity.children {
            applyReceivers(from: light, to: child)
        }
    }

    @MainActor
    private func removeReceivers(from entity: Entity) {
        entity.components.remove(ImageBasedLightReceiverComponent.self)
        for child in entity.children {
            removeReceivers(from: child)
        }
    }

    @MainActor
    private func applyVariant(to root: Entity) {
        guard !document.variants.isEmpty,
              document.variants.indices.contains(variantIndex)
        else { return }
        cacheOriginalMaterials(from: root)
        let mapping = document.variants[variantIndex].mapping
        let table = materialTable(in: root)
        applyVariantMapping(mapping, table: table, to: root)
    }

    @MainActor
    private func cacheOriginalMaterials(from entity: Entity) {
        let id = ObjectIdentifier(entity)
        if let model = entity.components[ModelComponent.self], cachedOriginalMaterials[id] == nil {
            cachedOriginalMaterials[id] = model.materials
        }
        for child in entity.children {
            cacheOriginalMaterials(from: child)
        }
    }

    @MainActor
    private func materialTable(in entity: Entity) -> [any RealityKit.Material]? {
        if let table = entity.components[GLTFMaterialTableComponent.self] {
            return table.materials
        }
        for child in entity.children {
            if let found = materialTable(in: child) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private func applyVariantMapping(
        _ mapping: [String: Int],
        table: [any RealityKit.Material]?,
        to entity: Entity
    ) {
        if var model = entity.components[ModelComponent.self] {
            let id = ObjectIdentifier(entity)
            var materials = cachedOriginalMaterials[id] ?? model.materials
            if let nodeIndex = entity.components[GLTFNodeIDComponent.self]?.nodeIndex,
               let meshIndex = node(at: nodeIndex)?.meshIndex {
                for primitiveIndex in materials.indices {
                    guard let materialIndex = mapping["\(meshIndex):\(primitiveIndex)"],
                          let table,
                          table.indices.contains(materialIndex)
                    else { continue }
                    materials[primitiveIndex] = table[materialIndex]
                }
            }
            model.materials = materials
            entity.components.set(model)
        }
        for child in entity.children {
            applyVariantMapping(mapping, table: table, to: child)
        }
    }

    @MainActor
    private func applyVisibility(to entity: Entity) {
        if let id = entity.components[GLTFNodeIDComponent.self]?.nodeIndex {
            let visible = !hide.contains(id) && !soloHides(id)
            if hasLightComponent(entity) {
                entity.isEnabled = visible && punctualLights
            } else {
                entity.isEnabled = visible
            }
        } else if hasLightComponent(entity) {
            entity.isEnabled = punctualLights
        }
        for child in entity.children {
            applyVisibility(to: child)
        }
    }

    private func ancestorIndices(of id: Int) -> Set<Int> {
        var found = Set<Int>()
        var current = id
        while let parent = document.nodes.first(where: { $0.children.contains(current) })?.index {
            found.insert(parent)
            current = parent
        }
        return found
    }

    func node(at index: Int) -> GLTFSessionDocument.Node? {
        document.nodes.first(where: { $0.index == index })
            ?? (document.nodes.indices.contains(index) ? document.nodes[index] : nil)
    }

    @MainActor
    private func hasLightComponent(_ entity: Entity) -> Bool {
        entity.components.has(PointLightComponent.self)
            || entity.components.has(SpotLightComponent.self)
            || entity.components.has(DirectionalLightComponent.self)
    }
}
