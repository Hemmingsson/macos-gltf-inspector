import Metal
import simd

public struct MetalOverlayOptions: Sendable {
    public var floor: Bool
    public var origin: Bool
    public var selectedNode: Int?
    public init(floor: Bool = false, origin: Bool = false, selectedNode: Int? = nil) {
        self.floor = floor; self.origin = origin; self.selectedNode = selectedNode
    }
}
struct MetalLineVertex { var position: SIMD4<Float>; var color: SIMD4<Float> }

func overlayVertices(scene: MetalScene, options: MetalOverlayOptions) -> [MetalLineVertex] {
    var vertices: [MetalLineVertex] = []
    func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD4<Float>) {
        vertices.append(MetalLineVertex(position: SIMD4(a, 1), color: color))
        vertices.append(MetalLineVertex(position: SIMD4(b, 1), color: color))
    }
    let extent = scene.boundsMax - scene.boundsMin
    let center = (scene.boundsMin + scene.boundsMax) / 2
    let scale = max(max(extent.x, extent.y), max(extent.z, 0.001))
    if options.floor {
        let radius = max(extent.x, extent.z) * 1.35
        let y = scene.boundsMin.y - scale * 0.005
        let color = SIMD4<Float>(0.55, 0.55, 0.55, 0.38)
        for ring in 1...4 {
            let r = radius * Float(ring) / 4
            for segment in 0..<128 {
                let a = Float(segment) * 2 * .pi / 128, b = Float(segment + 1) * 2 * .pi / 128
                line(SIMD3(center.x + cos(a) * r, y, center.z + sin(a) * r),
                     SIMD3(center.x + cos(b) * r, y, center.z + sin(b) * r), color)
            }
        }
        for radial in 0..<8 {
            let angle = Float(radial) * .pi / 4
            line(SIMD3(center.x, y, center.z), SIMD3(center.x + cos(angle) * radius, y, center.z + sin(angle) * radius), color)
        }
    }
    if options.origin {
        let length = scale * 0.25
        line(.zero, SIMD3(length, 0, 0), SIMD4(0.9, 0.25, 0.25, 1))
        line(.zero, SIMD3(0, length, 0), SIMD4(0.25, 0.8, 0.35, 1))
        line(.zero, SIMD3(0, 0, length), SIMD4(0.3, 0.5, 1, 1))
    }
    if let index = options.selectedNode, let bounds = scene.bounds(ofNode: index) {
        let lo = bounds.min, hi = bounds.max
        let corners = (0..<8).map { i in SIMD3<Float>(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z) }
        for i in 0..<8 {
            for bit in [1, 2, 4] where i & bit == 0 { line(corners[i], corners[i | bit], SIMD4(0.2, 0.55, 1, 1)) }
        }
    }
    return vertices
}
