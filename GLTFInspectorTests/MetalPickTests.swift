import Foundation
import Metal
import simd
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct MetalPickTests {
    private func device() throws -> any MTLDevice { try #require(MTLCreateSystemDefaultDevice()) }

    private func frontPose() -> MetalCameraPose {
        MetalCameraPose(azimuth: 0, elevation: 0, distance: 5, target: SIMD3(0, 0, 0),
                        yfov: .pi / 3, znear: 0.1, zfar: 100)
    }

    private func center(of size: Int) -> SIMD2<Int> { SIMD2(size / 2, size / 2) }

    @Test func stackedQuadsPickFrontThenBackWhenHidden() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let point = center(of: size)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: point) == 1)
        let hidden = ViewOptions(hiddenNodeIndices: [1])
        #expect(try renderer.pick(hidden, pose: frontPose(), width: size, height: size, point: point) == 0)
    }

    @Test func backgroundPixelReturnsNil() async throws {
        let url = try writeTempStackedQuadsGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: SIMD2(0, 0)) == nil)
    }

    @Test func maskHoleClicksThroughToMeshBehind() async throws {
        let url = try writeTempMaskOverOpaqueGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let center = center(of: size)
        #expect(try renderer.pick(ViewOptions(), pose: frontPose(), width: size, height: size, point: center) == 0)
        let onlyFront = ViewOptions(hiddenNodeIndices: [0])
        #expect(try renderer.pick(onlyFront, pose: frontPose(), width: size, height: size, point: center) == nil)
    }

    @Test func fileCameraUsesAuthoredView() async throws {
        let url = try writeTempCameraPickGLB()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let size = 64
        let point = center(of: size)
        #expect(try renderer.pick(ViewOptions(fileCameraNodeIndex: 1), pose: frontPose(),
                                  width: size, height: size, point: point) == 0)
    }
}
