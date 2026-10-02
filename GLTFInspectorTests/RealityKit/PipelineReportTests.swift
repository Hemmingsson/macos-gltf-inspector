import Foundation
@testable import GLTFCore
@testable import RendererRealityKit
import Testing

struct PipelineReportTests {
    @Test func cubePipelineIsStudioOnly() async throws {
        let url = TestFixtures.cube
        let model = try await EntityLoader.load(from: url)
        #expect(!model.pipelineReport.specGlossToMetalRough)
        #expect(!model.pipelineReport.dimmedStudioIBL)
        #expect(model.pipelineReport.entries.contains { $0.contains("Studio IBL: on") })
        #expect(model.pipelineReport.extensionsUsed.isEmpty)
    }

    @Test func loadSurfacesSourceExtensionsUsed() async throws {
        let data = try texturedPBRTriangleGLB(
            extensionsUsed: [
                "KHR_materials_clearcoat",
                "KHR_texture_transform",
            ],
            material: [
                "pbrMetallicRoughness": [
                    "baseColorTexture": [
                        "index": 0,
                        "extensions": [
                            "KHR_texture_transform": ["scale": [1, 1]],
                        ],
                    ],
                ],
                "extensions": [
                    "KHR_materials_clearcoat": [
                        "clearcoatFactor": 1,
                    ],
                ],
            ]
        )
        let url = try TestGLB.writeTemp(data, prefix: "ext-used")
        defer { try? FileManager.default.removeItem(at: url) }

        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(model.pipelineReport.extensionsUsed == [
            "KHR_materials_clearcoat",
            "KHR_texture_transform",
        ])
    }

    @Test func captureExtensionsDedupesAndSorts() {
        let names = RealityPipelineReport.captureExtensions(from: [
            "extensionsUsed": ["KHR_materials_unlit", "EXT_mesh_gpu_instancing", "KHR_materials_unlit"],
        ])
        #expect(names == ["EXT_mesh_gpu_instancing", "KHR_materials_unlit"])
    }
}
