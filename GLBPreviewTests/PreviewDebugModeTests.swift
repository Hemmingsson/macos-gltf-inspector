import Foundation
import RealityKit
import Testing
@testable import GLBPreview

struct PreviewDebugModeTests {
    @Test func titlesAndVariableValue() {
        #expect(PreviewDebugMode.none.shortTitle == "None")
        #expect(PreviewDebugMode.wire.shortTitle == "Wire")
        #expect(PreviewDebugMode.vertexColors.shortTitle == "RGB")
        #expect(PreviewDebugMode.visualization(.normal).shortTitle == "Nrm")
        #expect(PreviewDebugMode.visualization(.textureCoordinates).shortTitle == "UV")
        #expect(PreviewDebugMode.visualization(.lightingDiffuse).shortTitle == "Diff")
        #expect(PreviewDebugMode.visualization(.lightingSpecular).shortTitle == "LSpec")
    }

    @Test func baseAndUVMeshIncludesExpectedModes() {
        let json: [String: Any] = [
            "accessors": [["count": 3]],
            "meshes": [[
                "primitives": [[
                    "attributes": [
                        "POSITION": 0,
                        "TEXCOORD_0": 0,
                    ],
                    "indices": 0,
                ]],
            ]],
            "materials": [[
                "pbrMetallicRoughness": ["baseColorFactor": [1, 1, 1, 1]],
            ]],
        ]
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes.map(\.shortTitle) == ["None", "Wire", "UV", "Base", "Diff", "LSpec"])
        #expect(!modes.contains(.vertexColors))
    }

    @Test func occlusionAddsAO() {
        let json: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0, "NORMAL": 0],
                    "mode": 4,
                ]],
            ]],
            "materials": [[
                "occlusionTexture": ["index": 0],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles.contains("AO"))
        #expect(titles.contains("Nrm"))
        #expect(titles.contains("Wire"))
        #expect(titles.contains("Diff"))
        #expect(titles.contains("LSpec"))
    }

    @Test func unlitSkipsMetallicRoughness() {
        let json: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0],
                    "mode": 4,
                ]],
            ]],
            "materials": [[
                "extensions": ["KHR_materials_unlit": [:]],
                "pbrMetallicRoughness": [
                    "metallicFactor": 0,
                    "roughnessFactor": 0.2,
                ],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles == ["None", "Wire", "Base", "Diff", "LSpec"])
    }

    @Test func metalRoughTextureAddsMetAndRgh() {
        let json: [String: Any] = [
            "materials": [[
                "pbrMetallicRoughness": [
                    "metallicRoughnessTexture": ["index": 0],
                ],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles.contains("Met"))
        #expect(titles.contains("Rgh"))
        #expect(titles.contains("Base"))
        #expect(!titles.contains("Wire"))
        #expect(!titles.contains("Diff"))
    }

    @Test func vertexColorsAddsRGB() {
        let json: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": [
                        "POSITION": 0,
                        "COLOR_0": 0,
                    ],
                    "mode": 4,
                ]],
            ]],
        ]
        let titles = PreviewDebugMode.available(from: json).map(\.shortTitle)
        #expect(titles == ["None", "Wire", "Diff", "LSpec", "RGB"])
    }

    @Test func wrapUsesFilteredCount() {
        let modes = PreviewDebugMode.available(from: [
            "materials": [[:]],
        ])
        #expect(modes.first == Optional(PreviewDebugMode.none))
        let next = (0 + 1) % modes.count
        #expect(modes[next].shortTitle == "Base")
    }

    @MainActor
    @Test func vertexColorsReplacesWithWhiteUnlit() throws {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .red)
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [material])
        let store = DebugMaterialStore()

        PreviewDebugMode.apply(.vertexColors, to: entity, store: store)
        #expect(entity.components[ModelComponent.self]?.materials.first is UnlitMaterial)

        PreviewDebugMode.apply(.none, to: entity, store: store)
        let restored = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(restored.baseColor.tint.redComponent > 0.9)
    }

    @MainActor
    @Test func lightingDiffuseSetsDebugComponent() {
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial()])
        let store = DebugMaterialStore()
        PreviewDebugMode.apply(.visualization(.lightingDiffuse), to: entity, store: store)
        #expect(
            entity.components[ModelDebugOptionsComponent.self]?.visualizationMode == .lightingDiffuse
        )
    }

    @MainActor
    @Test func doubleSidedForcesFaceCullingNoneAndRestores() throws {
        var material = PhysicallyBasedMaterial()
        material.faceCulling = .back
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [material])
        let store = DebugMaterialStore()

        PreviewDebugMode.apply(.none, doubleSided: true, to: entity, store: store)
        let on = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(on.faceCulling == .none)

        PreviewDebugMode.apply(.none, doubleSided: false, to: entity, store: store)
        let off = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(off.faceCulling == .back)
    }

    @MainActor
    @Test func doubleSidedStacksWithWireThenRestores() throws {
        var material = PhysicallyBasedMaterial()
        material.faceCulling = .back
        material.triangleFillMode = .fill
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [material])
        let store = DebugMaterialStore()

        PreviewDebugMode.apply(.wire, doubleSided: true, to: entity, store: store)
        let both = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(both.faceCulling == .none)
        #expect(both.triangleFillMode == .lines)

        PreviewDebugMode.apply(.none, doubleSided: false, to: entity, store: store)
        let restored = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(restored.faceCulling == .back)
        #expect(restored.triangleFillMode == .fill)
    }

    @Test func availableDebugChannelsMapsRichVersusSparse() {
        let rich: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": [
                        "POSITION": 0,
                        "NORMAL": 0,
                        "TEXCOORD_0": 0,
                        "COLOR_0": 0,
                    ],
                    "mode": 4,
                ]],
            ]],
            "materials": [[
                "pbrMetallicRoughness": [
                    "metallicRoughnessTexture": ["index": 0],
                ],
                "occlusionTexture": ["index": 0],
                "emissiveTexture": ["index": 0],
            ]],
        ]
        let sparse: [String: Any] = [
            "meshes": [[
                "primitives": [[
                    "attributes": ["POSITION": 0],
                    "mode": 4,
                ]],
            ]],
        ]
        let richIDs = PreviewDebugMode.availableDebugChannels(from: rich).map(\.id)
        let sparseIDs = PreviewDebugMode.availableDebugChannels(from: sparse).map(\.id)
        #expect(richIDs.contains("normal"))
        #expect(richIDs.contains("metallic"))
        #expect(richIDs.contains("vertexColors"))
        #expect(richIDs.contains("lightingDiffuse"))
        #expect(!sparseIDs.contains("normal"))
        #expect(!sparseIDs.contains("metallic"))
        #expect(!sparseIDs.contains("vertexColors"))
        #expect(sparseIDs == ["none", "wire", "lightingDiffuse", "lightingSpecular"])
        #expect(richIDs.count > sparseIDs.count)
    }
}
