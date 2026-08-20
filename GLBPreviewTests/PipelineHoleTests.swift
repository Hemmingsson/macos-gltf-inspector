import AppKit
import CoreGraphics
import Foundation
import RealityKit
import Testing
import simd
@testable import GLBPreview

struct PipelineHoleTests {
    /// `convert(primitive:)` returns nil for anything except TRIANGLES and POINTS.
    @MainActor
    @Test func linesOnlyAssetHasNoVisibleMesh() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 1), prefix: "lines-only")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: Error.self) {
            _ = try await EntityLoader.load(from: url, includeAnimations: false)
        }
    }

    @MainActor
    @Test func triangleStripOnlyAssetHasNoVisibleMesh() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 5), prefix: "tristrip-only")
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: Error.self) {
            _ = try await EntityLoader.load(from: url, includeAnimations: false)
        }
    }

    @MainActor
    @Test func trianglesOnlyAssetLoads() async throws {
        let url = try GLBBox.writePrepared(try primitiveModeGLB(mode: 4), prefix: "tris-only")
        defer { try? FileManager.default.removeItem(at: url) }
        let model = try await EntityLoader.load(from: url, includeAnimations: false)
        #expect(EntityLoader.modelComponentCount(in: model.entity) > 0)
    }
}
