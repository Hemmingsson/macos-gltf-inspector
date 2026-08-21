import Foundation
import Observation

/// The UI-BUILD §2 fixture matrix, as one-click presets.
enum MockFixture: String, CaseIterable, Identifiable, Sendable {
    case plainMesh
    case riggedAnimated
    case multiScene
    case withLights
    case withCameras
    case missingChannels
    case invalidFile

    var id: Self { self }

    var title: String {
        switch self {
        case .plainMesh: "Plain mesh"
        case .riggedAnimated: "Rigged + animated"
        case .multiScene: "Multiple scenes"
        case .withLights: "With lights"
        case .withCameras: "With cameras"
        case .missingChannels: "Missing channels"
        case .invalidFile: "Invalid file"
        }
    }
}

/// The shell's model of "what this file contains", as independent flags.
///
/// Every flag maps to exactly one adaptive behaviour in the UI, so a single toggle shows
/// exactly one section or control appearing/disappearing. **All flags off == `plainMesh`.**
/// Slice 6 only binds these to a Debug menu; nothing else about this type changes.
@MainActor
@Observable
final class MockScene {
    var fileName: String = "Duck.glb"

    /// Shell load lifecycle — Debug menu drives empty / loading / failed for Slice 8 proofs.
    var documentState: ShellDocumentState = .ready

    var hasValidationWarnings: Bool = false
    var hasMultipleScenes: Bool = false
    var hasAnimations: Bool = false
    var hasLights: Bool = false
    var hasCameras: Bool = false
    var hasSkin: Bool = false
    var hasMorphs: Bool = false
    /// Materials and the view-mode menu lose the channels this file never authored.
    var hasMissingChannels: Bool = false
    /// The authored origin sits away from the model, so the origin gizmo has something to show.
    var isUncentered: Bool = false

    init() {}

    /// Snapshot of the current flags as a `SceneModel`.
    var model: MockSceneModel {
        MockSceneModel(
            fileName: fileName,
            scenes: scenes,
            nodeTree: nodeTree,
            cameras: cameras,
            lights: lights,
            materials: materials,
            animations: animations,
            skins: skins,
            morphs: morphs,
            stats: stats,
            dimensions: dimensions,
            validation: validation,
            pipelineReport: pipelineReport
        )
    }

    var availability: DerivedAvailability<MockSceneModel> {
        DerivedAvailability(model: model, channels: channels)
    }

    /// Set several flags at once to match a UI-BUILD §2 row.
    func apply(_ fixture: MockFixture) {
        documentState = .ready
        hasValidationWarnings = false
        hasMultipleScenes = false
        hasAnimations = false
        hasLights = false
        hasCameras = false
        hasSkin = false
        hasMorphs = false
        hasMissingChannels = false
        isUncentered = false

        switch fixture {
        case .plainMesh:
            break
        case .riggedAnimated:
            hasAnimations = true
            hasSkin = true
            hasMorphs = true
        case .multiScene:
            hasMultipleScenes = true
        case .withLights:
            hasLights = true
        case .withCameras:
            hasCameras = true
        case .missingChannels:
            hasMissingChannels = true
        case .invalidFile:
            hasValidationWarnings = true
            hasMissingChannels = true
            isUncentered = true
        }
    }

    // MARK: - Fixture data (invented; the engine track is irrelevant here)

    private var scenes: [SceneInfo] {
        var scenes = [SceneInfo(index: 0, name: "Scene 1", rootNodeIDs: [NodeID(kind: .mesh, index: 0)])]
        if hasMultipleScenes {
            scenes.append(SceneInfo(index: 1, name: "Scene 2", rootNodeIDs: [NodeID(kind: .mesh, index: 1)]))
        }
        return scenes
    }

    private var nodeTree: [SceneNode] {
        // ≥2 levels of mesh nesting so Meshes folding (chevron / guides / collapse) is visible.
        var roots: [SceneNode] = [
            SceneNode(
                kind: .mesh,
                index: 0,
                name: "Body",
                children: [
                    SceneNode(
                        kind: .mesh,
                        index: 1,
                        name: "Eyes",
                        children: [
                            SceneNode(kind: .mesh, index: 4, name: "Pupil")
                        ]
                    ),
                    SceneNode(kind: .mesh, index: 2, name: "Beak")
                ]
            )
        ]
        if hasSkin {
            roots.append(
                SceneNode(
                    kind: .empty,
                    index: 3,
                    name: "Armature",
                    children: [SceneNode(kind: .skin, index: 0, name: "Duck_Skin")]
                )
            )
        }
        if hasCameras {
            roots.append(SceneNode(kind: .camera, index: 0, name: "Camera_01"))
        }
        if hasLights {
            roots.append(SceneNode(kind: .light, index: 0, name: "Sun"))
            roots.append(SceneNode(kind: .light, index: 1, name: "Point.001"))
        }
        return roots
    }

    private var cameras: [CameraInfo] {
        guard hasCameras else { return [] }
        return [
            CameraInfo(
                index: 0,
                name: "Camera_01",
                projection: .perspective,
                fieldOfViewDegrees: 39.6,
                zNear: 0.1,
                zFar: 100
            )
        ]
    }

    private var lights: [LightInfo] {
        guard hasLights else { return [] }
        return [
            LightInfo(index: 0, name: "Sun", kind: .directional, intensity: 1_200),
            LightInfo(
                index: 1,
                name: "Point.001",
                kind: .point,
                color: RGBColor(red: 1, green: 0.86, blue: 0.7),
                intensity: 40,
                range: 6
            )
        ]
    }

    /// Channels this file has data for. `hasMissingChannels` strips the optional ones.
    private var channels: [DebugChannel] {
        if hasMissingChannels {
            return [.baseColor, .metallic, .roughness, .normals, .textureCoordinates]
        }
        return DebugChannel.allCases
    }

    /// Present maps for a complete PBR material. Emissive is deliberately absent so the
    /// inspector proves DESIGN.md's rule: missing maps omit their chip (never shown dimmed).
    private var fullMaps: Set<MaterialMap> {
        [.baseColor, .normal, .metallicRoughness, .occlusion]
    }

    private var reducedMaps: Set<MaterialMap> {
        [.baseColor, .metallicRoughness]
    }

    private var materials: [MaterialInfo] {
        if hasMissingChannels {
            return [
                MaterialInfo(
                    index: 0,
                    name: "Duck_Mat",
                    maps: reducedMaps,
                    textures: reducedTextures,
                    baseColorFactor: RGBColor(red: 0.95, green: 0.78, blue: 0.28),
                    metallicFactor: 0.05,
                    roughnessFactor: 0.7,
                    usedByMeshNames: ["Body", "Beak"],
                    usedByTriangleCount: 5_452,
                    uniqueTextureCount: 2
                ),
                MaterialInfo(
                    index: 1,
                    name: "Eye_Mat",
                    alphaMode: .opaque,
                    maps: reducedMaps.intersection([.baseColor, .metallicRoughness]),
                    textures: [
                        MaterialTextureInfo(
                            map: .baseColor,
                            width: 512,
                            height: 512,
                            previewColor: RGBColor(red: 0.12, green: 0.1, blue: 0.09)
                        ),
                        MaterialTextureInfo(
                            map: .metallicRoughness,
                            width: 512,
                            height: 512,
                            previewColor: RGBColor(red: 0.15, green: 0.4, blue: 0.3)
                        )
                    ],
                    baseColorFactor: RGBColor(red: 0.12, green: 0.1, blue: 0.09),
                    metallicFactor: 0,
                    roughnessFactor: 0.45,
                    usedByMeshNames: ["Eyes"],
                    usedByTriangleCount: 860,
                    uniqueTextureCount: 2
                )
            ]
        }
        return [
            MaterialInfo(
                index: 0,
                name: "Duck_Mat",
                workflow: .metallicRoughness,
                maps: fullMaps,
                textures: fullTextures,
                baseColorFactor: RGBColor(red: 1, green: 0.86, blue: 0.35),
                metallicFactor: 0.08,
                roughnessFactor: 0.62,
                normalScale: 1,
                occlusionStrength: 1,
                usedByMeshNames: ["Body", "Beak"],
                usedByTriangleCount: 5_452,
                uniqueTextureCount: 3
            ),
            MaterialInfo(
                index: 1,
                name: "Eye_Mat",
                alphaMode: .blend,
                isDoubleSided: true,
                maps: fullMaps.intersection([.baseColor, .metallicRoughness, .normal]),
                textures: eyeTextures,
                baseColorFactor: RGBColor(red: 0.14, green: 0.11, blue: 0.1),
                metallicFactor: 0,
                roughnessFactor: 0.38,
                usedByMeshNames: ["Eyes"],
                usedByTriangleCount: 860,
                uniqueTextureCount: 2
            )
        ]
    }

    private var fullTextures: [MaterialTextureInfo] {
        [
            MaterialTextureInfo(
                map: .baseColor,
                width: 2_048,
                height: 2_048,
                previewColor: RGBColor(red: 0.92, green: 0.72, blue: 0.25)
            ),
            MaterialTextureInfo(
                map: .normal,
                width: 2_048,
                height: 2_048,
                previewColor: RGBColor(red: 0.48, green: 0.52, blue: 1)
            ),
            MaterialTextureInfo(
                map: .metallicRoughness,
                width: 1_024,
                height: 1_024,
                previewColor: RGBColor(red: 0.18, green: 0.52, blue: 0.34)
            ),
            MaterialTextureInfo(
                map: .occlusion,
                width: 1_024,
                height: 1_024,
                previewColor: RGBColor(red: 0.42, green: 0.42, blue: 0.42)
            )
        ]
    }

    private var reducedTextures: [MaterialTextureInfo] {
        [
            MaterialTextureInfo(
                map: .baseColor,
                width: 1_024,
                height: 1_024,
                previewColor: RGBColor(red: 0.9, green: 0.7, blue: 0.22)
            ),
            MaterialTextureInfo(
                map: .metallicRoughness,
                width: 1_024,
                height: 1_024,
                previewColor: RGBColor(red: 0.2, green: 0.5, blue: 0.32)
            )
        ]
    }

    private var eyeTextures: [MaterialTextureInfo] {
        [
            MaterialTextureInfo(
                map: .baseColor,
                width: 512,
                height: 512,
                previewColor: RGBColor(red: 0.14, green: 0.11, blue: 0.1)
            ),
            MaterialTextureInfo(
                map: .normal,
                width: 512,
                height: 512,
                previewColor: RGBColor(red: 0.5, green: 0.55, blue: 1)
            ),
            MaterialTextureInfo(
                map: .metallicRoughness,
                width: 512,
                height: 512,
                texCoord: 1,
                previewColor: RGBColor(red: 0.16, green: 0.42, blue: 0.32)
            )
        ]
    }

    private var animations: [AnimationInfo] {
        guard hasAnimations else { return [] }
        return [
            AnimationInfo(index: 0, name: "Idle", duration: 70),
            AnimationInfo(index: 1, name: "Flap", duration: 12.5)
        ]
    }

    private var skins: [SkinInfo] {
        hasSkin ? [SkinInfo(index: 0, name: "Duck_Skin", jointCount: 24)] : []
    }

    private var morphs: [MorphInfo] {
        hasMorphs ? [MorphInfo(index: 0, meshName: "Body", targetNames: ["Blink", "Smile"])] : []
    }

    private var stats: Stats {
        Stats(
            triangleCount: 12_480,
            vertexCount: 7_310,
            meshCount: 4,
            materialCount: materials.count,
            textureCount: hasMissingChannels ? 2 : 4,
            maxTextureDimension: 2_048,
            animationCount: animations.count,
            fileSizeBytes: 1_258_291,
            hasVertexColors: false,
            isRigged: hasSkin,
            morphTargetCount: morphs.reduce(0) { $0 + $1.targetNames.count }
        )
    }

    private var dimensions: Dimensions {
        Dimensions(
            width: 1.24,
            height: 0.86,
            depth: 1.10,
            authoredOrigin: isUncentered ? Vector3(x: 0.42, y: 0, z: -0.10) : .zero
        )
    }

    private var validation: ValidationResult {
        guard hasValidationWarnings else { return ValidationResult() }
        return ValidationResult(issues: [
            ValidationResult.Issue(
                severity: .warning,
                message: "Body — missing tangents; normal map may render wrong.",
                pointer: "/meshes/0/primitives/0"
            ),
            ValidationResult.Issue(
                severity: .warning,
                message: "Texture spec.png is declared but unused.",
                pointer: "/images/2"
            ),
            ValidationResult.Issue(
                severity: .warning,
                message: "Node Empty.003 has no children and no mesh.",
                pointer: "/nodes/7"
            )
        ])
    }

    private var pipelineReport: PipelineReport {
        var entries: [PipelineReport.Entry] = [
            PipelineReport.Entry(title: "Converted from KHR spec-gloss"),
            PipelineReport.Entry(title: "Dequantized mesh", detail: "KHR_mesh_quantization")
        ]
        entries.append(
            PipelineReport.Entry(
                kind: .lighting,
                title: "Lighting",
                detail: "File lights: \(hasLights ? "on" : "off") · Studio IBL: on"
            )
        )
        return PipelineReport(entries: entries)
    }
}

/// Value-type `SceneModel` the shell hands the UI. Built by `MockScene`; never mutated.
struct MockSceneModel: SceneModel {
    var fileName: String
    var scenes: [SceneInfo]
    var nodeTree: [SceneNode]
    var cameras: [CameraInfo]
    var lights: [LightInfo]
    var materials: [MaterialInfo]
    var animations: [AnimationInfo]
    var skins: [SkinInfo]
    var morphs: [MorphInfo]
    var stats: Stats
    var dimensions: Dimensions
    var validation: ValidationResult
    var pipelineReport: PipelineReport
}
