import CoreGraphics
import Foundation
import GLTFCore
import Metal
import QuartzCore
import simd

public enum MetalRendererError: Error, LocalizedError {
    case unavailable, resource(String), gpu(String), noScene
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Metal is unavailable."
        case .resource(let message): "Metal resource: \(message)"
        case .gpu(let message): "Metal GPU: \(message)"
        case .noScene: "No model has been loaded."
        }
    }
}

/// Native Khronos renderer. One instance has one caller; loading and drawing must not overlap.
/// GPU resources stay in this extension-safe framework; the host owns its presentation view.
public final class MetalRenderer: @unchecked Sendable {
    public let device: any MTLDevice
    let queue: any MTLCommandQueue
    let library: any MTLLibrary
    public private(set) var scene: MetalScene?
    public private(set) var gpuMilliseconds = 0.0
    public private(set) var pipelineMilliseconds = 0.0
    var overlayPipeline: (any MTLRenderPipelineState)?
    var overlayCopyPipeline: (any MTLRenderPipelineState)?
    private var presentationPipeline: (any MTLRenderPipelineState)?
    private var pipelines: [String: any MTLRenderPipelineState] = [:]
    private let tonePipeline: any MTLRenderPipelineState
    private let depthWrite: any MTLDepthStencilState
    private let depthRead: any MTLDepthStencilState
    private var environment: MetalEnvironment?
    private var materialResources: [ObjectIdentifier: MetalMaterialResources] = [:]
    private var environmentID: KhronosEnvironments?
    /// Khronos keeps its drawable lists across frames and re-sorts them in place, so depth ties
    /// keep the previous frame's order. Rebuilt on every load, like `prepareScene` on new nodes.
    private var drawLists = MetalDrawLists(draws: [])

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw MetalRendererError.unavailable
        }
        self.device = device
        self.queue = queue
        library = try device.makeDefaultLibrary(bundle: Bundle(for: MetalRenderer.self))
        let tone = MTLRenderPipelineDescriptor()
        tone.vertexFunction = library.makeFunction(name: "khronos_tonemap_vertex")
        tone.fragmentFunction = library.makeFunction(name: "khronos_tonemap_fragment")
        tone.colorAttachments[0].pixelFormat = .rgba8Unorm
        tonePipeline = try device.makeRenderPipelineState(descriptor: tone)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = true
        guard let write = device.makeDepthStencilState(descriptor: depth) else { throw MetalRendererError.resource("depth") }
        depthWrite = write
        depth.isDepthWriteEnabled = false
        guard let read = device.makeDepthStencilState(descriptor: depth) else { throw MetalRendererError.resource("depth read") }
        depthRead = read
    }

    public func load(url: URL, sceneIndex: Int? = nil, materialVariantIndex: Int? = nil) async throws {
        materialResources.removeAll()
        let loaded = try await MetalSceneLoader.load(url: url, device: device, sceneIndex: sceneIndex, materialVariantIndex: materialVariantIndex)
        scene = loaded
        drawLists = MetalDrawLists(draws: loaded.draws)
    }

    public static func still(url: URL, look: RenderLook, pose: MetalCameraPose, size: Int) async throws -> CGImage {
        let renderer = try MetalRenderer()
        try await renderer.load(url: url)
        return try renderer.still(look: look, pose: pose, size: size)
    }

    public func still(look: RenderLook, pose: MetalCameraPose, size: Int, orthographic: Bool = false,
                      debugOutput: Int = 0, wireframe: Bool = false, overlays: MetalOverlayOptions = .init(), fileCameraNodeIndex: Int? = nil) throws -> CGImage {
        try image(look: look, pose: pose, width: size, height: size, orthographic: orthographic,
                  debugOutput: debugOutput, wireframe: wireframe, overlays: overlays, fileCameraNodeIndex: fileCameraNodeIndex)
    }

    public func image(look: RenderLook, pose: MetalCameraPose, width: Int, height: Int,
                      orthographic: Bool = false, debugOutput: Int = 0, wireframe: Bool = false, overlays: MetalOverlayOptions = .init(), fileCameraNodeIndex: Int? = nil) throws -> CGImage {
        let output = try renderTexture(look: look, pose: pose, width: width, height: height,
                                       orthographic: orthographic, debugOutput: debugOutput, wireframe: wireframe, overlays: overlays, fileCameraNodeIndex: fileCameraNodeIndex)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        output.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // WebGL's premultiplied canvas is quantized to RGBA8 before PNG unpremultiplication.
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[offset + 3])
            if alpha > 0 && alpha < 255 {
                for component in 0..<3 {
                    bytes[offset + component] = UInt8(min(255, (Int(bytes[offset + component]) * 255 + alpha / 2) / alpha))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { throw MetalRendererError.resource("image readback") }
        return image
    }

    public func renderTexture(look: RenderLook, pose: MetalCameraPose, width: Int, height: Int,
                              orthographic: Bool = false, debugOutput: Int = 0,
                              wireframe: Bool = false, overlays: MetalOverlayOptions = .init(), fileCameraNodeIndex: Int? = nil) throws -> any MTLTexture {
        guard let scene else { throw MetalRendererError.noScene }
        guard width > 0, height > 0, width <= 16384, height <= 16384 else {
            throw MetalRendererError.resource("invalid image size")
        }
        if environmentID != look.environment {
            environment = try MetalEnvironment.shared(device: device, library: library, queue: queue, environment: look.environment)
            environmentID = look.environment
        }
        let camera = MetalCamera(pose: pose, isOrthographic: orthographic, aspect: Float(width) / Float(height))
        var frame = GPUFrame(viewProjection: camera.openGLProjectionMatrix * camera.viewMatrix,
                             cameraPosition: SIMD4(camera.eye, 1),
                             environment: SIMD4(Float((90 + look.environmentYawDegrees) * .pi / 180),
                                                Float(look.environmentIntensity) * (environment?.intensityScale ?? 1),
                                                Float(pow(2, look.exposureEV)), 4),
                             options: SIMD4(toneMap(look.toneMapping), UInt32(debugOutput), environment == nil ? 0 : 1, UInt32(scene.lights.count)),
                             viewport: SIMD4(Float(width), Float(height), 0, 0))
        var view = camera.viewMatrix
        // Khronos letterboxes to the camera's own aspect: the user camera's square ortho, or a
        // file camera's aspectRatio / xmag÷ymag.
        var viewportAspect: Float? = orthographic ? 1 : nil
        if let index = fileCameraNodeIndex, let fileCamera = scene.fileCamera(at: index, aspect: Float(width) / Float(height)) {
            frame.viewProjection = fileCamera.viewProjection
            frame.cameraPosition = SIMD4(fileCamera.eye, 1)
            view = fileCamera.view
            viewportAspect = fileCamera.viewportAspect
        }
        let viewport = khronosViewport(width: width, height: height, aspect: viewportAspect)
        let hdr = try texture(.rgba16Float, width, height, [.renderTarget, .shaderRead])
        let flags = try texture(.r8Uint, width, height, [.renderTarget, .shaderRead])
        let depth = try texture(.depth32Float, width, height, [.renderTarget])
        let output = try texture(.rgba8Unorm, width, height, [.renderTarget, .shaderRead], storage: .shared)
        guard let command = queue.makeCommandBuffer() else { throw MetalRendererError.resource("command buffer") }
        command.label = "Khronos still"
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = hdr
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        // clearFrame: the tonemap flag attachment clears to 1 (linear to sRGB).
        pass.colorAttachments[1].texture = flags
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].storeAction = .store
        pass.colorAttachments[1].clearColor = MTLClearColorMake(1, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        let black = try texture(.rgba8Unorm, 1, 1, [.shaderRead], storage: .shared)
        var clear: UInt32 = 0
        black.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clear, bytesPerRow: 4)
        let order = drawLists.frame(draws: scene.draws, view: view)
        var background: any MTLTexture = black
        if let prepass = order.transmissionPrepass {
            background = try transmissionBackground(command: command, frame: frame, scene: scene, draws: prepass,
                                                    fallback: black, wireframe: wireframe)
        }
        try encodeScene(command: command, pass: pass, frame: frame, scene: scene,
                        draws: order.main, background: background, wireframe: wireframe, viewport: viewport)
        let tone = MTLRenderPassDescriptor()
        tone.colorAttachments[0].texture = output
        // Outside a letterboxed viewport the canvas keeps its transparent clear.
        tone.colorAttachments[0].loadAction = viewportAspect == nil ? .dontCare : .clear
        tone.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        tone.colorAttachments[0].storeAction = .store
        guard let finish = command.makeRenderCommandEncoder(descriptor: tone) else { throw MetalRendererError.resource("tonemap encoder") }
        finish.setViewport(viewport)
        finish.setRenderPipelineState(tonePipeline)
        finish.setFragmentTexture(hdr, index: 0)
        finish.setFragmentTexture(flags, index: 1)
        finish.setFragmentBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        finish.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finish.endEncoding()
        let lines = overlayVertices(scene: scene, options: overlays)
        if !lines.isEmpty {
            try encodeOverlays(lines, command: command, output: output,
                               viewProjection: camera.openGLProjectionMatrix * camera.viewMatrix, viewport: viewport)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw MetalRendererError.gpu(error.localizedDescription) }
        gpuMilliseconds = max(0, command.gpuEndTime - command.gpuStartTime) * 1000
        return output
    }

    public func present(_ texture: any MTLTexture, on drawable: any CAMetalDrawable) throws {
        if presentationPipeline == nil {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "khronos_tonemap_vertex")
            d.fragmentFunction = library.makeFunction(name: "khronos_present_fragment")
            d.colorAttachments[0].pixelFormat = drawable.texture.pixelFormat
            presentationPipeline = try device.makeRenderPipelineState(descriptor: d)
        }
        guard let command = queue.makeCommandBuffer(), let pipeline = presentationPipeline else {
            throw MetalRendererError.resource("presentation command")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw MetalRendererError.resource("presentation encoder")
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }

    private func transmissionBackground(command: any MTLCommandBuffer, frame: GPUFrame,
                                        scene: MetalScene, draws: [Int],
                                        fallback: any MTLTexture, wireframe: Bool = false) throws -> any MTLTexture {
        let resolution = 1024
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
            width: resolution, height: resolution, mipmapped: true)
        d.storageMode = .private
        d.usage = [.renderTarget, .shaderRead]
        guard let resolved = device.makeTexture(descriptor: d) else { throw MetalRendererError.resource("transmission resolve") }
        func multisample(_ format: MTLPixelFormat) throws -> any MTLTexture {
            let m = MTLTextureDescriptor()
            m.textureType = .type2DMultisample
            m.pixelFormat = format
            m.width = resolution; m.height = resolution
            m.sampleCount = 4
            m.storageMode = .private
            m.usage = [.renderTarget]
            guard let made = device.makeTexture(descriptor: m) else { throw MetalRendererError.resource("transmission MSAA") }
            return made
        }
        let color = try multisample(.rgba8Unorm)
        let flag = try multisample(.r8Uint)
        let depth = try multisample(.depth32Float)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].resolveTexture = resolved
        pass.colorAttachments[0].loadAction = .clear
        // clearFrame clears opaqueFramebufferMSAA to clearColor^2.2; the page's clearColor is [0, 0, 0, 0].
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .storeAndMultisampleResolve
        pass.colorAttachments[1].texture = flag
        pass.colorAttachments[1].loadAction = .clear
        pass.colorAttachments[1].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        var preFrame = frame
        preFrame.options.z |= 2
        try encodeScene(command: command, pass: pass, frame: preFrame, scene: scene,
            draws: draws, background: fallback, samples: 4, format: .rgba8Unorm, wireframe: wireframe)
        guard let blit = command.makeBlitCommandEncoder() else { throw MetalRendererError.resource("transmission mips") }
        blit.generateMipmaps(for: resolved)
        blit.endEncoding()
        return resolved
    }

    private func encodeScene(command: any MTLCommandBuffer, pass: MTLRenderPassDescriptor,
                             frame inputFrame: GPUFrame, scene: MetalScene,
                             draws: [Int], background: any MTLTexture,
                             samples: Int = 1, format: MTLPixelFormat = .rgba16Float,
                             wireframe: Bool = false, viewport: MTLViewport? = nil) throws {
        var frame = inputFrame
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw MetalRendererError.resource("render encoder") }
        if let viewport { encoder.setViewport(viewport) }
        encoder.setVertexBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        if wireframe { encoder.setTriangleFillMode(.lines) }
        environment?.bind(encoder)
        encoder.setFragmentTexture(background, index: 30)
        var lights = scene.lights.map(GPULight.init)
        if lights.isEmpty { lights = [GPULight.zero] }
        lights.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4) }
        for index in draws {
            let draw = scene.draws[index]
            let blend = draw.material.alphaMode == 2
            encoder.setRenderPipelineState(try pipeline(blend: blend, samples: samples, format: format))
            encoder.setDepthStencilState(blend ? depthRead : depthWrite)
            encoder.setCullMode(draw.material.doubleSided ? .none : .back)
            encoder.setFrontFacing(draw.negativeScale ? .clockwise : .counterClockwise)
            var uniforms = GPUDraw(model: draw.worldTransform, normalMatrix: draw.worldTransform.inverse.transpose)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUDraw>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUDraw>.stride, index: 2)
            var material = GPUMaterial(draw.material)
            encoder.setFragmentBytes(&material, length: MemoryLayout<GPUMaterial>.stride, index: 3)
            encoder.setVertexBytes(&material, length: MemoryLayout<GPUMaterial>.stride, index: 3)
            let resourceKey = ObjectIdentifier(draw.vertexBuffer)
            if materialResources[resourceKey] == nil {
                materialResources[resourceKey] = try MetalMaterialResources(draw.material, device: device, library: library)
            }
            materialResources[resourceKey]?.bind(encoder)
            encoder.setVertexBuffer(draw.vertexBuffer, offset: 0, index: 0)
            encoder.drawIndexedPrimitives(type: draw.primitiveType, indexCount: draw.indexCount, indexType: .uint32,
                                          indexBuffer: draw.indexBuffer, indexBufferOffset: 0)
        }
        encoder.endEncoding()
    }

    private func pipeline(blend: Bool, samples: Int = 1, format: MTLPixelFormat = .rgba16Float) throws -> any MTLRenderPipelineState {
        let key = "\(blend)-\(samples)-\(format.rawValue)"
        if let cached = pipelines[key] { return cached }
        let start = CFAbsoluteTimeGetCurrent()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "khronos_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "khronos_fragment")
        descriptor.colorAttachments[0].pixelFormat = format
        descriptor.rasterSampleCount = samples
        descriptor.colorAttachments[1].pixelFormat = .r8Uint
        descriptor.depthAttachmentPixelFormat = .depth32Float
        if blend {
            let color = descriptor.colorAttachments[0]!
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .sourceAlpha
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        let made = try device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[key] = made
        pipelineMilliseconds += (CFAbsoluteTimeGetCurrent() - start) * 1000
        return made
    }

    private func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int, _ usage: MTLTextureUsage,
                         storage: MTLStorageMode = .private) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = usage
        d.storageMode = storage
        guard let texture = device.makeTexture(descriptor: d) else { throw MetalRendererError.resource("texture \(format)") }
        return texture
    }
}

/// Port of the Khronos drawable lists: `prepareScene` grouping and `drawScene` ordering.
struct MetalDrawLists {
    /// Opaque and mask drawables without `KHR_materials_transmission`, in `Object.groupBy` order.
    private(set) var opaque: [Int]
    /// `alphaMode` BLEND without `KHR_materials_transmission`.
    private(set) var transparent: [Int]
    /// Every drawable whose material has `KHR_materials_transmission`, whatever its alpha mode.
    private(set) var transmission: [Int]

    struct Frame: Equatable {
        /// Opaque then sorted transparent drawables; nil when the scene has no transmission drawables.
        var transmissionPrepass: [Int]?
        /// Opaque, then sorted transmission, then sorted transparent drawables in front of the camera.
        var main: [Int]
    }

    init(draws: [MetalDraw]) {
        var groups: [String: [Int]] = [:], keys: [String] = []
        var transparent: [Int] = [], transmission: [Int] = []
        for (index, draw) in draws.enumerated() {
            if draw.material.hasTransmission {
                transmission.append(index)
            } else if draw.material.alphaMode == 2 {
                transparent.append(index)
            } else {
                // Group keys always contain "_", so the object keeps insertion order.
                if groups[draw.opaqueGroup] == nil { keys.append(draw.opaqueGroup) }
                groups[draw.opaqueGroup, default: []].append(index)
            }
        }
        // Each instancing group is one instanced draw at its first member's position.
        opaque = keys.flatMap { groups[$0] ?? [] }
        self.transparent = transparent
        self.transmission = transmission
    }

    /// One `drawScene`. The lists are re-sorted in place, as upstream does every frame.
    mutating func frame(draws: [MetalDraw], view: simd_float4x4) -> Frame {
        var prepass: [Int]?
        var transparentDepths: [Float] = []
        if !transmission.isEmpty {
            (transparent, transparentDepths) = Self.sortedByDepth(transparent, draws: draws, view: view)
            prepass = opaque + transparent
        }
        let transmissionDepths: [Float]
        (transmission, transmissionDepths) = Self.sortedByDepth(transmission, draws: draws, view: view)
        (transparent, transparentDepths) = Self.sortedByDepth(transparent, draws: draws, view: view)
        // `filter((a) => a.depth <= 0)`: drawables whose centroid is behind the camera are skipped.
        let front = { (list: [Int], depths: [Float]) in zip(list, depths).filter { $0.1 <= 0 }.map(\.0) }
        return Frame(transmissionPrepass: prepass,
                     main: opaque + front(transmission, transmissionDepths) + front(transparent, transparentDepths))
    }

    /// `Camera.sortPrimitivesByDepth`: the view-space Z of the primitive centroid, ascending
    /// (farthest first), with `Array.prototype.sort`'s stability.
    static func sortedByDepth(_ list: [Int], draws: [MetalDraw], view: simd_float4x4) -> ([Int], [Float]) {
        var items = list.map { ($0, viewDepth(of: draws[$0], view: view)) }
        // Stable merge sort; the right item moves first only when `a.depth - b.depth > 0`.
        var buffer = items
        var width = 1
        while width < items.count {
            var start = 0
            while start < items.count {
                let middle = min(start + width, items.count), end = min(start + 2 * width, items.count)
                var left = start, right = middle, out = start
                while left < middle && right < end {
                    if items[left].1 - items[right].1 > 0 { buffer[out] = items[right]; right += 1 }
                    else { buffer[out] = items[left]; left += 1 }
                    out += 1
                }
                while left < middle { buffer[out] = items[left]; left += 1; out += 1 }
                while right < end { buffer[out] = items[right]; right += 1; out += 1 }
                start = end
            }
            swap(&items, &buffer)
            width *= 2
        }
        return (items.map(\.0), items.map(\.1))
    }

    /// gl-matrix `multiply(view, world)` then `transformMat4(centroid)`: double arithmetic,
    /// Float32 storage, divided by w (or 1 when w is 0).
    static func viewDepth(of draw: MetalDraw, view: simd_float4x4) -> Float {
        let world = draw.worldTransform
        func modelView(_ column: Int, _ row: Int) -> Double {
            var sum = 0.0
            for k in 0..<4 { sum += Double(world[column][k]) * Double(view[k][row]) }
            return Double(Float(sum))
        }
        let x = Double(draw.centroid.x), y = Double(draw.centroid.y), z = Double(draw.centroid.z)
        var w = modelView(0, 3) * x + modelView(1, 3) * y + modelView(2, 3) * z + modelView(3, 3)
        if w == 0 || w.isNaN { w = 1 }
        return Float((modelView(0, 2) * x + modelView(1, 2) * y + modelView(2, 2) * z + modelView(3, 2)) / w)
    }
}

private struct GPUFrame {
    var viewProjection: simd_float4x4
    var cameraPosition: SIMD4<Float>
    var environment: SIMD4<Float>
    var options: SIMD4<UInt32>
    var viewport: SIMD4<Float>
}

private struct GPUDraw { var model: simd_float4x4; var normalMatrix: simd_float4x4 }
private func toneMap(_ mapping: RenderLook.ToneMapping) -> UInt32 {
    switch mapping { case .pbrNeutral: 0; case .none: 1; case .acesNarkowicz: 2; case .acesHill: 3 }
}
