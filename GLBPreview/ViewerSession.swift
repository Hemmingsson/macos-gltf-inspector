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
    let defaultExponent: Float
    let document: GLTFSessionDocument
    weak var boundRoot: Entity?
    weak var boundIBL: Entity?

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
    }

    func layerRootIndices() -> [Int] {
        guard document.scenes.indices.contains(activeSceneIndex) else { return [] }
        return document.scenes[activeSceneIndex].rootNodeIndices
    }

    func bind(root: Entity, iblEntity: Entity?) {
        boundRoot = root
        boundIBL = iblEntity
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

        applyPunctual(to: root)
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
    private func applyPunctual(to entity: Entity) {
        if hasLightComponent(entity) {
            entity.isEnabled = punctualLights
        }
        for child in entity.children {
            applyPunctual(to: child)
        }
    }

    @MainActor
    private func hasLightComponent(_ entity: Entity) -> Bool {
        entity.components.has(PointLightComponent.self)
            || entity.components.has(SpotLightComponent.self)
            || entity.components.has(DirectionalLightComponent.self)
    }
}
