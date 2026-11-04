import GLTFCore
import Metal
import simd

/// How the main pass draws each mesh for the display view modes. Wireframe is a fill mode on
/// the shaded pass (`encodeScene(wireframe:)`), and debug channels draw `.shaded` with their
/// channel output, so both map to `.shaded` here.
enum MetalDrawStyle: Equatable {
    case shaded
    /// The second pass of wireframe-on-shaded: every edge, flat and unlit, over the frame.
    case wireframeOnShaded
    case xray
    case clay

    static let xrayOpacity: Float = 0.4
    /// `frame.options.z` bit for the tone-map pass: map straight colour, not premultiplied.
    static let straightToneMapBit: UInt32 = 8
    /// Edge colour for wireframe-on-shaded (linear, before tone mapping).
    static let edgeColor = SIMD4<Float>(0.06, 0.06, 0.07, 1)

    init(_ mode: RenderViewMode) {
        self = switch mode {
        case .wireframeOnShaded: .wireframeOnShaded
        case .xray: .xray
        case .clay: .clay
        case .shaded, .wireframe, .channel: .shaded
        }
    }

    /// The material this style draws a mesh with.
    func material(for source: MetalMaterial) -> MetalMaterial {
        switch self {
        case .shaded, .xray: source
        case .clay: .clay(like: source)
        case .wireframeOnShaded: .edges(like: source)
        }
    }

    /// X-ray blends every mesh; otherwise only BLEND materials do.
    func blends(_ material: MetalMaterial) -> Bool {
        self == .xray || material.alphaMode == 2
    }

    /// X-ray shows the far side of closed shapes; edges are drawn for both faces.
    var drawsBackFaces: Bool { self == .xray || self == .wireframeOnShaded }

    /// X-ray: the shader's BLEND path at reduced opacity.
    func adjust(_ material: inout GPUMaterial) {
        guard self == .xray else { return }
        material.baseColor.w *= Self.xrayOpacity
        material.flags.y = 2
    }

    /// Lines, nudged toward the camera so an edge wins the depth test against its own face.
    func configureEdgePass(_ encoder: any MTLRenderCommandEncoder) {
        encoder.setTriangleFillMode(.lines)
        encoder.setDepthBias(-1, slopeScale: -1, clamp: 0)
    }

    static func hasTriangles(_ draw: MetalDraw) -> Bool {
        draw.primitiveType == .triangle || draw.primitiveType == .triangleStrip
    }
}

extension MetalMaterial {
    /// Clay: one neutral matte grey material, no maps, no extensions. Keeps what the vertex layout
    /// says (UVs, normals, tangents) and the authored sidedness.
    static func clay(like source: MetalMaterial) -> MetalMaterial {
        var clay = MetalMaterial()
        // 18 % (photographic mid) grey: Blender's 0.8 reads as white under the Khronos lighting.
        clay.baseColor = SIMD4(0.18, 0.18, 0.18, 1)
        clay.metallic = 0
        clay.roughness = 0.6
        clay.doubleSided = source.doubleSided
        clay.hasTexCoord0 = source.hasTexCoord0
        clay.hasNormal = source.hasNormal
        clay.hasTangent = source.hasTangent
        return clay
    }

    /// The flat, unlit edge material of wireframe-on-shaded.
    static func edges(like source: MetalMaterial) -> MetalMaterial {
        var edges = clay(like: source)
        edges.unlit = true
        edges.baseColor = MetalDrawStyle.edgeColor
        return edges
    }
}
