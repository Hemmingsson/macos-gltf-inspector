import Foundation
import RealityKit
@testable import RendererRealityKit
import Testing

private let diffuse = PreviewDebugMode.visualization(.lightingDiffuse)
private let lightSpecular = PreviewDebugMode.visualization(.lightingSpecular)

struct PreviewDebugModeTests {
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
        #expect(modes == [.none, .wire, .visualization(.textureCoordinates), .visualization(.baseColor), diffuse, lightSpecular])
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
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes.contains(.visualization(.ambientOcclusion)))
        #expect(modes.contains(.visualization(.normal)))
        #expect(modes.contains(.wire))
        #expect(modes.contains(diffuse))
        #expect(modes.contains(lightSpecular))
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
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes == [.none, .wire, .visualization(.baseColor), diffuse, lightSpecular])
    }

    @Test func metalRoughTextureAddsMetAndRgh() {
        let json: [String: Any] = [
            "materials": [[
                "pbrMetallicRoughness": [
                    "metallicRoughnessTexture": ["index": 0],
                ],
            ]],
        ]
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes.contains(.visualization(.metallic)))
        #expect(modes.contains(.visualization(.roughness)))
        #expect(modes.contains(.visualization(.baseColor)))
        #expect(!modes.contains(.wire))
        #expect(!modes.contains(diffuse))
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
        let modes = PreviewDebugMode.available(from: json)
        #expect(modes == [.none, .wire, diffuse, lightSpecular, .vertexColors])
    }

    @Test func wrapUsesFilteredCount() {
        let modes = PreviewDebugMode.available(from: [
            "materials": [[:]],
        ])
        #expect(modes.first == Optional(PreviewDebugMode.none))
        let next = (0 + 1) % modes.count
        #expect(modes[next] == .visualization(.baseColor))
    }

    @MainActor
    @Test func vertexColorsReplacesWithWhiteUnlit() throws {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .red)
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [material])
        let store = DebugMaterialStore()

        PreviewDebugMode.apply(.vertexColors, doubleSided: false, to: entity, store: store)
        #expect(entity.components[ModelComponent.self]?.materials.first is UnlitMaterial)

        PreviewDebugMode.apply(.none, doubleSided: false, to: entity, store: store)
        let restored = try #require(
            entity.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial
        )
        #expect(restored.baseColor.tint.redComponent > 0.9)
    }

    @MainActor
    @Test func lightingDiffuseSetsDebugComponent() {
        let entity = ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial()])
        let store = DebugMaterialStore()
        PreviewDebugMode.apply(.visualization(.lightingDiffuse), doubleSided: false, to: entity, store: store)
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

    @Test func availableModesRichVersusSparse() {
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
        let richModes = PreviewDebugMode.available(from: rich)
        let sparseModes = PreviewDebugMode.available(from: sparse)
        #expect(richModes.contains(.visualization(.normal)))
        #expect(richModes.contains(.visualization(.metallic)))
        #expect(richModes.contains(.vertexColors))
        #expect(richModes.contains(diffuse))
        #expect(sparseModes == [.none, .wire, diffuse, lightSpecular])
        #expect(richModes.count > sparseModes.count)
    }
}
