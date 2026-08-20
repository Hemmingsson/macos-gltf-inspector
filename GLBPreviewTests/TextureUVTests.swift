import simd
import Testing
@testable import GLBPreview

struct TextureUVTests {
    @Test func wrapsSingleNonZeroTile() {
        let uvs = [SIMD2<Float>(2.1, 3.2), SIMD2<Float>(2.8, 3.9)]
        let wrapped = TextureUV.wrapSingleTile(uvs)
        #expect(abs(wrapped[0].x - 0.1) < 0.0001)
        #expect(abs(wrapped[0].y - 0.2) < 0.0001)
        #expect(abs(wrapped[1].x - 0.8) < 0.0001)
        #expect(abs(wrapped[1].y - 0.9) < 0.0001)
    }

    @Test func leavesUnitSquareAlone() {
        let uvs = [SIMD2<Float>(0.01, 0.02), SIMD2<Float>(0.99, 0.98)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }

    @Test func leavesMultiTileSpanAlone() {
        let uvs = [SIMD2<Float>(0.1, 0.2), SIMD2<Float>(2.1, 0.2)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }

    @Test func leavesSlightNegativePaddingAlone() {
        let uvs = [SIMD2<Float>(-0.01, 0.1), SIMD2<Float>(0.9, 0.9)]
        #expect(TextureUV.wrapSingleTile(uvs) == uvs)
    }
}
