import CoreGraphics
import Testing
@testable import Renderer

@MainActor
@Suite(.serialized)
struct SelectionOutlineTests {
    private static let size = 128
    private static let pose = MetalCameraPose(azimuth: 35, elevation: -20, distance: 4, target: .zero,
                                              yfov: .pi / 3, znear: 0.1, zfar: 100)

    private func render(_ renderer: MetalRenderer, options: ViewOptions) throws -> CGImage {
        try renderer.image(options, pose: Self.pose, width: Self.size, height: Self.size)
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    private func isOutlineAccent(_ bytes: [UInt8], offset: Int) -> Bool {
        let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2]), a = Int(bytes[offset + 3])
        guard a > 200 else { return false }
        return r < 80 && g > 150 && b > 200
    }

    @Test func meshSelectionUsesSilhouetteNotAABB() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let scene = try #require(renderer.scene)
        #expect(usesSilhouetteSelectionOutline(nodeIndex: 0, scene: scene))
        #expect(overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0)).isEmpty)
    }

    @Test func groupSelectionKeepsAABBOverlay() async throws {
        let url = try writeTempGroupedMeshGLB(prefix: "group-aabb")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        let scene = try #require(renderer.scene)
        #expect(!usesSilhouetteSelectionOutline(nodeIndex: 0, scene: scene))
        #expect(overlayVertices(scene: scene, options: MetalOverlayOptions(selectedNode: 0)).count == 24)
    }

    @Test func emptySelectionMatchesUnselectedRender() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let baseline = pixels(try render(renderer, options: ViewOptions()))
        let again = pixels(try render(renderer, options: ViewOptions(selectedNodeIndex: nil)))
        #expect(baseline == again)
    }

    @Test func selectedMeshDrawsOutlineWithoutInteriorFill() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let bytes = pixels(try render(renderer, options: ViewOptions(selectedNodeIndex: 0)))
        let width = Self.size, height = Self.size
        let unselected = pixels(try render(renderer, options: ViewOptions()))
        var outline = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            guard isOutlineAccent(bytes, offset: offset) else { continue }
            outline += 1
            #expect(!isOutlineAccent(unselected, offset: offset), "outline must not appear without selection")
        }
        #expect(outline > 40, "the silhouette ring should be visible")
        #expect(outline < width * height / 8, "outline must stay a thin ring, not a fill")
    }

    @Test func outlineMovesWhenTheCameraChanges() async throws {
        let renderer = try MetalRenderer()
        try await renderer.load(url: TestFixtures.cube)
        let options = ViewOptions(selectedNodeIndex: 0)
        let front = pixels(try render(renderer, options: options))
        let sidePose = MetalCameraPose(azimuth: 90, elevation: -12, distance: 4, target: .zero,
                                       yfov: .pi / 3, znear: 0.1, zfar: 100)
        let side = pixels(try renderer.image(options, pose: sidePose, width: Self.size, height: Self.size))
        var diff = 0
        for i in stride(from: 0, to: front.count, by: 4) {
            if isOutlineAccent(front, offset: i) != isOutlineAccent(side, offset: i) { diff += 1 }
        }
        #expect(diff > 20, "outline pixels should follow the projected silhouette")
    }
}
