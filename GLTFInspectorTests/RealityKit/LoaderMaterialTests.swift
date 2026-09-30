import AppKit
import CoreGraphics
import Foundation
import RealityKit
@testable import RendererRealityKit
import simd
import Testing

struct LoaderHelpersTests {
    @MainActor
    @Test func modelComponentCountWalksTree() {
        let root = Entity()
        #expect(EntityLoader.modelComponentCount(in: root) == 0)
        root.addChild(ModelEntity(mesh: .generateBox(size: 0.2), materials: [SimpleMaterial()]))
        #expect(EntityLoader.modelComponentCount(in: root) == 1)
    }

    /// End-to-end proof of the fused load pipeline: single header parse → convert →
    /// `LoadedModel` with stats, against a real `.glb`.
    @MainActor
    @Test func loadsRealGLBEndToEnd() async throws {
        let url = TestFixtures.tiny
        try #require(FileManager.default.fileExists(atPath: url.path))
        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)
        #expect(model.stats.triangleCount > 0)
    }

    /// glTF metal/rough has no extra gem specular. RealityKit defaults that
    /// knob to 0.5, which makes dielectrics (paper, cloth) pick up IBL like metal.
    @MainActor
    @Test func metalRoughLeavesDielectricSpecularOff() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("paper.glb")
        try metalRoughTriangleGLB().write(to: url)
        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        let pbr = pbrMaterials(in: model.entity)
        try #require(!pbr.isEmpty)
        for material in pbr {
            #expect(material.specular.scale == 0)
        }
    }

    @MainActor
    @Test func skipsNormalMapWhenScaleIsZero() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            material: [
                "normalTexture": ["index": 0, "scale": 0],
                "pbrMetallicRoughness": [
                    "baseColorTexture": ["index": 0],
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ]
        ))
        #expect(material.normal.texture == nil)
    }

    @MainActor
    @Test func mapsKHRSpecularFactor() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            extensionsUsed: ["KHR_materials_specular"],
            material: [
                "extensions": [
                    "KHR_materials_specular": ["specularFactor": 0.4],
                ],
                "pbrMetallicRoughness": [
                    "metallicFactor": 0,
                    "roughnessFactor": 0.7,
                ],
            ]
        ))
        #expect(abs(material.specular.scale - 0.4) < 0.001)
    }

    @MainActor
    @Test func mapsKHRTextureTransformToTheMaterial() async throws {
        let glb = try texturedPBRTriangleGLB(
            extensionsUsed: ["KHR_texture_transform"],
            material: [
                "pbrMetallicRoughness": [
                    "baseColorTexture": [
                        "index": 0,
                        "extensions": [
                            "KHR_texture_transform": [
                                "offset": [0.1, 0.2],
                                "scale": [2.0, 3.0],
                            ],
                        ],
                    ],
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ],
            uvs: [(0, 0), (1, 0), (0, 1)]
        )
        let loaded = try await loadModel(glb)
        let pbr = pbrMaterials(in: loaded.entity)
        try #require(!pbr.isEmpty)
        // The transform is a material parameter (glTF offset / scale carry over), not baked.
        let materialUV = pbr[0].textureCoordinateTransform
        #expect(abs(materialUV.scale.x - 2) < 0.001)
        #expect(abs(materialUV.scale.y - 3) < 0.001)
        #expect(abs(materialUV.offset.x - 0.1) < 0.001)
        #expect(abs(materialUV.offset.y - 0.2) < 0.001)

        let uvs = try #require(firstMeshUVs(in: loaded.entity))
        try #require(uvs.count >= 3)
        // Authored UVs, only V flipped for RealityKit.
        #expect(uvs[0] == SIMD2(0, 1))
        #expect(uvs[1] == SIMD2(1, 1))
        #expect(uvs[2] == SIMD2(0, 0))
    }

    /// UVs outside 0–1 stay where the file put them: the sampler (REPEAT by default, or the
    /// file's CLAMP) decides, as the spec says. The old single-UDIM-tile shift broke CLAMP
    /// (TextureSettingsTest's clamp rows failed).
    @MainActor
    @Test func keepsUVsOutsideTheUnitSquare() async throws {
        let glb = try texturedPBRTriangleGLB(
            material: [
                "pbrMetallicRoughness": [
                    "baseColorTexture": ["index": 0],
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ],
            uvs: [(2.1, 3.2), (2.8, 3.2), (2.1, 3.9)]
        )
        let uvs = try #require(firstMeshUVs(in: try await loadModel(glb).entity))
        try #require(uvs.count >= 3)
        #expect(abs(uvs[0].x - 2.1) < 0.001)
        #expect(abs(uvs[0].y - (1 - 3.2)) < 0.001)
    }

    @MainActor
    @Test func blendUsesBaseColorAlpha() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            material: [
                "alphaMode": "BLEND",
                "pbrMetallicRoughness": [
                    "baseColorFactor": [1, 1, 1, 0.25],
                    "baseColorTexture": ["index": 0],
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ]
        ))
        guard case .transparent(let opacity) = material.blending else {
            Issue.record("expected transparent blending")
            return
        }
        #expect(abs(opacity.scale - 0.25) < 0.001)
        #expect(opacity.texture != nil)
    }

    @MainActor
    @Test func mapsEmissiveFactor() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            material: [
                "emissiveFactor": [0.2, 0.4, 0.6],
                "pbrMetallicRoughness": [
                    "metallicFactor": 0,
                    "roughnessFactor": 1,
                ],
            ]
        ))
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let components = material.emissiveColor.color.cgColor
            .converted(to: linear, intent: .defaultIntent, options: nil)?
            .components
        try #require(components != nil && components!.count >= 3)
        #expect(abs(Float(components![0]) - 0.2) < 0.02)
        #expect(abs(Float(components![1]) - 0.4) < 0.02)
        #expect(abs(Float(components![2]) - 0.6) < 0.02)
        #expect(abs(material.emissiveIntensity - 1) < 0.001)
    }

    @MainActor
    @Test func ignoresAlbedoCopiedAsEmissive() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            material: [
                "emissiveFactor": [1, 1, 1],
                "emissiveTexture": ["index": 0],
                "pbrMetallicRoughness": [
                    "baseColorTexture": ["index": 0],
                    "metallicFactor": 0,
                    "roughnessFactor": 0.6,
                ],
            ]
        ))
        #expect(!hasVisibleEmissive(material))
    }

    @MainActor
    @Test func ignoresFileWideWhiteEmissiveBoost() async throws {
        let materials: [[String: Any]] = [
            [
                "emissiveFactor": [1, 1, 1],
                "pbrMetallicRoughness": ["metallicFactor": 1, "roughnessFactor": 1],
            ],
            [
                "emissiveFactor": [1, 1, 1],
                "pbrMetallicRoughness": ["metallicFactor": 1, "roughnessFactor": 1],
            ],
        ]
        let pbr = try await loadAllPBR(try multiMaterialTriangleGLB(materials: materials))
        #expect(pbr.count == 2)
        for material in pbr {
            #expect(!hasVisibleEmissive(material))
        }
    }

    @MainActor
    @Test func keepsHighStrengthEmissiveWhenFileLooksBaked() async throws {
        let materials: [[String: Any]] = [
            [
                "emissiveFactor": [1, 1, 1],
                "extensions": ["KHR_materials_emissive_strength": ["emissiveStrength": 4]],
                "pbrMetallicRoughness": ["metallicFactor": 0, "roughnessFactor": 1],
            ],
            [
                "emissiveFactor": [1, 1, 1],
                "pbrMetallicRoughness": ["metallicFactor": 0, "roughnessFactor": 1],
            ],
        ]
        let pbr = try await loadAllPBR(try multiMaterialTriangleGLB(
            extensionsUsed: ["KHR_materials_emissive_strength"],
            materials: materials
        ))
        try #require(pbr.count == 2)
        #expect(abs(pbr[0].emissiveIntensity - 4) < 0.01)
        #expect(!hasVisibleEmissive(pbr[1]))
    }

    @MainActor
    @Test func mapsClearcoatNormal() async throws {
        let material = try await loadFirstPBR(try texturedPBRTriangleGLB(
            extensionsUsed: ["KHR_materials_clearcoat"],
            material: [
                "extensions": [
                    "KHR_materials_clearcoat": [
                        "clearcoatFactor": 1,
                        "clearcoatNormalTexture": ["index": 0],
                    ],
                ],
                "pbrMetallicRoughness": [
                    "metallicFactor": 0,
                    "roughnessFactor": 0.2,
                ],
            ]
        ))
        #expect(abs(material.clearcoat.scale - 1) < 0.001)
        #expect(material.clearcoatNormal.texture != nil)
    }
}
