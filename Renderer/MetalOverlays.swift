import Metal
import simd

/// Inspector chrome viewer.html draws after the Khronos frame (`drawOverlays`): the polar floor,
/// the authored-origin gizmo and the selected subtree's box. Same geometry, colours and pass:
/// opaque 1-pixel lines, no depth occlusion (the canvas depth is cleared and the tonemap quad
/// writes none), the user camera even while a file camera draws the model, and the page's
/// antialiased canvas — 4× MSAA, seeded with the tonemapped frame.
struct MetalOverlayOptions: Sendable {
    var floor: Bool
    var origin: Bool
    var selectedNode: Int?
    /// `camera.sceneExtents`: what the page sizes the floor and gizmo by. When centring is off it
    /// includes the origin. Nil uses the scene's drawn bounds.
    var extents: (min: SIMD3<Float>, max: SIMD3<Float>)?
    init(floor: Bool = false, origin: Bool = false, selectedNode: Int? = nil,
                extents: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil) {
        self.floor = floor; self.origin = origin; self.selectedNode = selectedNode; self.extents = extents
    }
}
struct MetalLineVertex { var position: SIMD4<Float>; var color: SIMD4<Float> }

func overlayVertices(scene: MetalScene, options: MetalOverlayOptions) -> [MetalLineVertex] {
    var vertices: [MetalLineVertex] = []
    func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD3<Float>) {
        vertices.append(MetalLineVertex(position: SIMD4(a, 1), color: SIMD4(color, 1)))
        vertices.append(MetalLineVertex(position: SIMD4(b, 1), color: SIMD4(color, 1)))
    }
    // viewer.html `sceneBounds`.
    let low = options.extents?.min ?? scene.boundsMin
    let high = options.extents?.max ?? scene.boundsMax
    let extent = simd_max(high - low, SIMD3(repeating: 1e-4))
    if options.floor {
        // `collectPolarFloor`: centred on the world origin, just under the scene.
        let radius = max(2.7 * max(extent.x, extent.z) * 0.5, 0.001)
        let y = low.y - 0.001
        let color = SIMD3<Float>(0.53, 0.53, 0.53)
        let rings = 4, radials = 8, segments = 64
        for ring in 1...rings {
            let r = radius * Float(ring) / Float(rings)
            var previous: SIMD3<Float>?
            for i in 0...segments {
                let a = Double(i) / Double(segments) * .pi * 2
                let p = SIMD3(Float(cos(a)) * r, y, Float(sin(a)) * r)
                if let previous { line(previous, p, color) }
                previous = p
            }
        }
        let inner = max(radius * 0.03, 0.002)
        for i in 0..<radials {
            let a = Double(i) / Double(radials) * .pi * 2
            let c = Float(cos(a)), s = Float(sin(a))
            line(SIMD3(c * inner, y, s * inner), SIMD3(c * radius, y, s * radius), color)
        }
    }
    if options.origin {
        // `collectOriginGizmo`.
        let size = 0.18 * max(extent.x, extent.y, extent.z, 0.05)
        line(.zero, SIMD3(size, 0, 0), SIMD3(1, 0.2, 0.2))
        line(.zero, SIMD3(0, size, 0), SIMD3(0.2, 1, 0.2))
        line(.zero, SIMD3(0, 0, size), SIMD3(0.25, 0.45, 1))
    }
    if let index = options.selectedNode, let box = scene.bounds(ofNode: index) {
        // `collectAABB`: padded by 1% of the longest side.
        let size = box.max - box.min
        let pad = 0.01 * max(size.x, size.y, size.z, 0.01)
        let a = box.min - pad, b = box.max + pad
        let corners: [SIMD3<Float>] = [
            SIMD3(a.x, a.y, a.z), SIMD3(b.x, a.y, a.z), SIMD3(a.x, b.y, a.z), SIMD3(b.x, b.y, a.z),
            SIMD3(a.x, a.y, b.z), SIMD3(b.x, a.y, b.z), SIMD3(a.x, b.y, b.z), SIMD3(b.x, b.y, b.z),
        ]
        let edges = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]
        for (i, j) in edges { line(corners[i], corners[j], SIMD3(0.15, 0.75, 1)) }
    }
    return vertices
}

extension MetalRenderer {
    /// Draws `lines` over the tonemapped `output` the way the page draws them over its canvas.
    /// `viewProjection` is the user camera's WebGL clip transform; `viewport` the Khronos one.
    func encodeOverlays(_ lines: [MetalLineVertex], command: any MTLCommandBuffer, output: any MTLTexture,
                        viewProjection: simd_float4x4, viewport: MTLViewport) throws {
        let samples = 4
        if overlayPipeline == nil || overlayCopyPipeline == nil {
            let line = MTLRenderPipelineDescriptor()
            line.vertexFunction = library.makeFunction(name: "khronos_line_vertex")
            line.fragmentFunction = library.makeFunction(name: "khronos_line_fragment")
            line.colorAttachments[0].pixelFormat = output.pixelFormat
            line.rasterSampleCount = samples
            overlayPipeline = try device.makeRenderPipelineState(descriptor: line)
            let copy = MTLRenderPipelineDescriptor()
            copy.vertexFunction = library.makeFunction(name: "khronos_tonemap_vertex")
            copy.fragmentFunction = library.makeFunction(name: "khronos_overlay_copy_fragment")
            copy.colorAttachments[0].pixelFormat = output.pixelFormat
            copy.rasterSampleCount = samples
            overlayCopyPipeline = try device.makeRenderPipelineState(descriptor: copy)
        }
        guard let linePipeline = overlayPipeline, let copyPipeline = overlayCopyPipeline else {
            throw MetalRendererError.resource("overlay pipelines")
        }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DMultisample
        descriptor.pixelFormat = output.pixelFormat
        descriptor.width = output.width
        descriptor.height = output.height
        descriptor.sampleCount = samples
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget]
        guard let multisample = device.makeTexture(descriptor: descriptor) else {
            throw MetalRendererError.resource("overlay MSAA target")
        }
        // The frame is resolved back into `output`, so read a copy of it.
        let copyDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: output.pixelFormat,
            width: output.width, height: output.height, mipmapped: false)
        copyDescriptor.storageMode = .private
        copyDescriptor.usage = [.shaderRead]
        guard let frame = device.makeTexture(descriptor: copyDescriptor), let blit = command.makeBlitCommandEncoder() else {
            throw MetalRendererError.resource("overlay frame copy")
        }
        blit.copy(from: output, to: frame)
        blit.endEncoding()
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = multisample
        pass.colorAttachments[0].resolveTexture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .multisampleResolve
        // WebGL draws its canvas bottom-up, so the standard 4× pattern lands mirrored in the
        // image the page reads back. Mirror it here so line coverage matches sample for sample.
        if device.areProgrammableSamplePositionsSupported {
            pass.setSamplePositions(device.getDefaultSamplePositions(sampleCount: samples).map {
                MTLSamplePosition(x: $0.x, y: 1 - $0.y)
            })
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass),
              let buffer = lines.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { throw MetalRendererError.resource("overlays") }
        encoder.label = "Overlays"
        encoder.setRenderPipelineState(copyPipeline)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.setViewport(viewport)
        encoder.setRenderPipelineState(linePipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        var matrix = viewProjection
        encoder.setVertexBytes(&matrix, length: MemoryLayout<simd_float4x4>.stride, index: 1)
        encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lines.count)
        encoder.endEncoding()
    }
}
