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
/// `ModelView` presents its frames; stills are read back.
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
    private var pickPipelines: [UInt32: any MTLRenderPipelineState] = [:]
    private var capturePipelines: [UInt32: any MTLRenderPipelineState] = [:]
    private let tonePipeline: any MTLRenderPipelineState
    private let depthWrite: any MTLDepthStencilState
    private let depthRead: any MTLDepthStencilState
    private var environment: MetalEnvironment?
    private var materialResources: [ObjectIdentifier: MetalMaterialResources] = [:]
    private var environmentID: LightingEnvironment?
    /// Khronos keeps its drawable lists across frames and re-sorts them in place, so depth ties
    /// keep the previous frame's order. Rebuilt on every load, like `prepareScene` on new nodes.
    private var drawLists = MetalDrawLists(draws: [])
    /// The draw mask of the last filter, so an idle filter is not re-resolved every frame. The
    /// scene identifier is only meaningful while that scene is alive, so `load` clears this.
    private var drawVisibility: (filter: MetalDrawFilter, scene: ObjectIdentifier, visible: [Bool])?

    public convenience init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw MetalRendererError.unavailable }
        try self.init(device: device)
    }

    /// A second renderer for the same loaded scene (e.g. an inspector preview): shared GPU
    /// buffers, its own draw lists, pipelines and material resources.
    public convenience init(sharing scene: MetalScene) throws {
        guard let draw = scene.draws.first else { throw MetalRendererError.noScene }
        try self.init(device: draw.vertexBuffer.device)
        try adopt(scene)
    }

    private init(device: any MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else { throw MetalRendererError.unavailable }
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

    /// Points at an already-loaded scene and rebuilds draw lists. Pipelines and per-renderer
    /// material caches stay on this instance; `MetalEnvironment.shared` is unchanged.
    public func adopt(_ loaded: MetalScene) throws {
        guard let draw = loaded.draws.first else { throw MetalRendererError.noScene }
        guard draw.vertexBuffer.device === device else { throw MetalRendererError.resource("device mismatch") }
        materialResources.removeAll()
        scene = loaded
        drawLists = MetalDrawLists(draws: loaded.draws)
        drawVisibility = nil
    }

    /// `sceneIndex` nil draws the file's default scene.
    public func load(url: URL, sceneIndex: Int? = nil, materialVariantIndex: Int? = nil) async throws {
        let loaded = try await MetalSceneLoader.load(url: url, device: device, sceneIndex: sceneIndex, materialVariantIndex: materialVariantIndex)
        try adopt(loaded)
    }

    /// One frame read back as straight-alpha sRGB. `extents` sizes the floor and origin gizmo
    /// (the camera's measured box); nil uses the drawn bounds. The transmission prepass is
    /// Khronos's 1024²; thumbnails pass a smaller edge to save memory.
    public func image(_ options: ViewOptions, pose: MetalCameraPose, width: Int, height: Int,
                      extents: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil,
                      transmissionResolution: Int = 1024,
                      animationPose: AnimationPose? = nil) throws -> CGImage {
        let output = try renderTexture(options, pose: pose, width: width, height: height, extents: extents,
                                       transmissionResolution: transmissionResolution, animationPose: animationPose)
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

    /// `centerOffset` moves the orbit camera's projection centre by that many pixels (x right,
    /// y up); the live canvas uses it to centre the model beside the sidebar and inspector.
    /// User-camera view-projection and letterbox aspect for overlay-aligned gizmo hit tests.
    func gizmoPickFrame(options: ViewOptions, pose: MetalCameraPose, width: Int, height: Int,
                        centerOffset: SIMD2<Float> = .zero) throws -> (viewProjection: simd_float4x4, viewportAspect: Float?) {
        guard scene != nil else { throw MetalRendererError.noScene }
        let setup = try sceneFrameSetup(options: options, pose: pose, width: width, height: height,
                                        centerOffset: centerOffset, scene: scene!)
        return (setup.camera.openGLProjectionMatrix * setup.camera.viewMatrix, setup.viewportAspect)
    }

    /// glTF node index under `point` (x right, y down), or nil for background / mask holes.
    func pick(_ options: ViewOptions, pose: MetalCameraPose, width: Int, height: Int,
              centerOffset: SIMD2<Float> = .zero, point: SIMD2<Int>) throws -> Int? {
        guard let scene else { throw MetalRendererError.noScene }
        guard width > 0, height > 0, width <= 16384, height <= 16384 else {
            throw MetalRendererError.resource("invalid image size")
        }
        let setup = try sceneFrameSetup(options: options, pose: pose, width: width, height: height,
                                        centerOffset: centerOffset, scene: scene)
        let pickTarget = try texture(.r32Uint, width, height, [.renderTarget, .shaderRead])
        let depth = try texture(.depth32Float, width, height, [.renderTarget])
        guard let command = queue.makeCommandBuffer() else { throw MetalRendererError.resource("command buffer") }
        command.label = "Khronos pick"
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = pickTarget
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        try encodePick(command: command, pass: pass, frame: setup.frame, scene: scene,
                       draws: setup.mainDraws, transforms: setup.transforms, viewport: setup.viewport)
        let x = min(max(point.x, 0), width - 1)
        let y = min(max(point.y, 0), height - 1)
        let readback = try texture(.r32Uint, 1, 1, [.shaderRead], storage: .shared)
        guard let blit = command.makeBlitCommandEncoder() else { throw MetalRendererError.resource("pick blit") }
        blit.copy(from: pickTarget, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: x, y: y, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                  to: readback, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw MetalRendererError.gpu(error.localizedDescription) }
        var drawID: UInt32 = 0
        readback.getBytes(&drawID, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        guard drawID > 0, Int(drawID) <= scene.draws.count else { return nil }
        return scene.draws[Int(drawID) - 1].nodeIndex
    }

    func renderTexture(_ options: ViewOptions, pose: MetalCameraPose, width: Int, height: Int,
                       extents: (min: SIMD3<Float>, max: SIMD3<Float>)? = nil,
                       transmissionResolution: Int = 1024,
                       centerOffset: SIMD2<Float> = .zero,
                       animationPose: AnimationPose? = nil) throws -> any MTLTexture {
        guard let scene else { throw MetalRendererError.noScene }
        guard width > 0, height > 0, width <= 16384, height <= 16384 else {
            throw MetalRendererError.resource("invalid image size")
        }
        let wireframe = options.viewMode == .wireframe
        let overlays = MetalOverlayOptions(options, canvasAspect: Float(width) / Float(height), extents: extents)
        let setup = try sceneFrameSetup(options: options, pose: pose, width: width, height: height,
                                        centerOffset: centerOffset, scene: scene, animationPose: animationPose)
        var frame = setup.frame
        let viewportAspect = setup.viewportAspect
        let viewport = setup.viewport
        let lights = setup.lights
        let order = MetalDrawLists.Frame(transmissionPrepass: setup.transmissionPrepass, main: setup.mainDraws)
        let hdr = try texture(.rgba16Float, width, height, [.renderTarget, .shaderRead])
        let flags = try texture(.r8Uint, width, height, [.renderTarget, .shaderRead])
        // Stored for overlay soft depth: floor / gizmo / AABB must sit behind the model.
        let depth = try texture(.depth32Float, width, height, [.renderTarget, .shaderRead])
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
        pass.depthAttachment.storeAction = .store
        pass.depthAttachment.clearDepth = 1
        let black = try texture(.rgba8Unorm, 1, 1, [.shaderRead], storage: .shared)
        var clear: UInt32 = 0
        black.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &clear, bytesPerRow: 4)
        var background: any MTLTexture = black
        if let prepass = order.transmissionPrepass {
            background = try transmissionBackground(command: command, frame: frame, scene: scene, draws: prepass,
                                                    transforms: setup.transforms, lights: lights, fallback: black,
                                                    wireframe: wireframe, resolution: transmissionResolution,
                                                    animationPose: animationPose)
        }
        try encodeScene(command: command, pass: pass, frame: frame, scene: scene, lights: lights,
                        draws: order.main, transforms: setup.transforms, background: background,
                        wireframe: wireframe, style: MetalDrawStyle(options.viewMode), viewport: viewport,
                        animationPose: animationPose)
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
        if MetalDrawStyle(options.viewMode) == .xray { frame.options.z |= MetalDrawStyle.straightToneMapBit }
        finish.setFragmentBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        finish.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        finish.endEncoding()
        let lines = overlayVertices(scene: scene, options: overlays)
        if !lines.isEmpty {
            // Overlays always use the user camera; only occlude when that camera also drew the model.
            try encodeOverlays(lines, command: command, output: output,
                               viewProjection: setup.camera.openGLProjectionMatrix * setup.camera.viewMatrix, viewport: viewport,
                               sceneDepth: depth, occlude: options.fileCameraNodeIndex == nil)
        }
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw MetalRendererError.gpu(error.localizedDescription) }
        gpuMilliseconds = max(0, command.gpuEndTime - command.gpuStartTime) * 1000
        return output
    }

    /// Draw transforms and depth order for one frame. Encoding reads `transforms`; hide, solo and
    /// isolate still drop draws after the sort.
    struct MetalFrameDraws {
        var transforms: [DrawFrameTransform]
        var main: [Int]
        var transmissionPrepass: [Int]?
    }

    func frameDraws(options: ViewOptions, animationPose: AnimationPose?, view: simd_float4x4) -> MetalFrameDraws {
        guard let scene else { return MetalFrameDraws(transforms: [], main: [], transmissionPrepass: nil) }
        let transforms = scene.drawTransforms(pose: animationPose)
        var order = drawLists.frame(draws: scene.draws, models: transforms.map(\.model), view: view)
        let filter = MetalDrawFilter(options)
        if !filter.isEmpty {
            let visible = visibility(of: filter, in: scene)
            order.main = order.main.filter { visible[$0] }
            order.transmissionPrepass = order.transmissionPrepass?.filter { visible[$0] }
        }
        return MetalFrameDraws(transforms: transforms, main: order.main, transmissionPrepass: order.transmissionPrepass)
    }

    private struct SceneFrameSetup {
        var frame: GPUFrame
        var view: simd_float4x4
        var viewport: MTLViewport
        var viewportAspect: Float?
        var lights: [MetalPunctualLight]
        var transforms: [DrawFrameTransform]
        var mainDraws: [Int]
        var transmissionPrepass: [Int]?
        var camera: MetalCamera
    }

    private func sceneFrameSetup(options: ViewOptions, pose: MetalCameraPose, width: Int, height: Int,
                                 centerOffset: SIMD2<Float>, scene: MetalScene,
                                 animationPose: AnimationPose? = nil) throws -> SceneFrameSetup {
        let look = options.look
        let orthographic = options.isOrthographic
        if environmentID != look.environment {
            environment = try MetalEnvironment.shared(device: device, environment: look.environment)
            environmentID = look.environment
        }
        var camera = MetalCamera(pose: pose, isOrthographic: orthographic, aspect: Float(width) / Float(height))
        if centerOffset != .zero {
            let cameraViewport = khronosViewport(width: width, height: height, aspect: orthographic ? 1 : nil)
            camera.centerShift = 2 * centerOffset / SIMD2(Float(cameraViewport.width), Float(cameraViewport.height))
        }
        let filter = MetalDrawFilter(options)
        let lights = filter.visibleLights(in: scene)
        var frame = GPUFrame(viewProjection: camera.openGLProjectionMatrix * camera.viewMatrix,
                             cameraPosition: SIMD4(camera.eye, 1),
                             environment: SIMD4(Float((90 + look.environmentYawDegrees) * .pi / 180),
                                                Float(look.environmentIntensity) * (environment?.intensityScale ?? 1),
                                                Float(pow(2, look.exposureEV)), 4),
                             options: SIMD4(toneMap(look.toneMapping), debugOutput(options.viewMode), environment == nil ? 0 : 1, UInt32(lights.count)),
                             viewport: SIMD4(Float(width), Float(height), 0, 0))
        var view = camera.viewMatrix
        var viewportAspect: Float? = orthographic ? 1 : nil
        if let index = options.fileCameraNodeIndex, let fileCamera = scene.fileCamera(at: index, aspect: Float(width) / Float(height)) {
            frame.viewProjection = fileCamera.viewProjection
            frame.cameraPosition = SIMD4(fileCamera.eye, 1)
            view = fileCamera.view
            viewportAspect = fileCamera.viewportAspect
        }
        let viewport = khronosViewport(width: width, height: height, aspect: viewportAspect)
        let posed = frameDraws(options: options, animationPose: animationPose, view: view)
        return SceneFrameSetup(frame: frame, view: view, viewport: viewport, viewportAspect: viewportAspect,
                               lights: lights, transforms: posed.transforms, mainDraws: posed.main,
                               transmissionPrepass: posed.transmissionPrepass, camera: camera)
    }

    private func visibility(of filter: MetalDrawFilter, in scene: MetalScene) -> [Bool] {
        let identifier = ObjectIdentifier(scene)
        if let cached = drawVisibility, cached.filter == filter, cached.scene == identifier {
            return cached.visible
        }
        let visible = filter.visibleDraws(in: scene)
        drawVisibility = (filter, identifier, visible)
        return visible
    }

    func present(_ texture: any MTLTexture, on drawable: any CAMetalDrawable) throws {
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
                                        scene: MetalScene, draws: [Int], transforms: [DrawFrameTransform],
                                        lights: [MetalPunctualLight],
                                        fallback: any MTLTexture, wireframe: Bool = false,
                                        resolution requested: Int = 1024,
                                        animationPose: AnimationPose? = nil) throws -> any MTLTexture {
        // Khronos's prepass is 1024². Thumbnail stills pass a smaller edge; never grow past 1024.
        let resolution = min(1024, max(1, requested))
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
        // clearFrame clears opaqueFramebufferMSAA to clearColor^2.2; the viewer's clearColor is [0, 0, 0, 0].
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
        try encodeScene(command: command, pass: pass, frame: preFrame, scene: scene, lights: lights,
            draws: draws, transforms: transforms, background: fallback, samples: 4, format: .rgba8Unorm,
            wireframe: wireframe, animationPose: animationPose)
        guard let blit = command.makeBlitCommandEncoder() else { throw MetalRendererError.resource("transmission mips") }
        blit.generateMipmaps(for: resolved)
        blit.endEncoding()
        return resolved
    }

    /// Index is a scene draw index. A missing entry keeps the rest model, which is what a still encodes.
    private func frameTransform(_ transforms: [DrawFrameTransform], _ index: Int, _ draw: MetalDraw) -> DrawFrameTransform {
        if transforms.indices.contains(index) { return transforms[index] }
        return DrawFrameTransform(model: draw.worldTransform,
                                  normalMatrix: draw.worldTransform.inverse.transpose,
                                  negativeScale: draw.negativeScale)
    }

    private func encodeScene(command: any MTLCommandBuffer, pass: MTLRenderPassDescriptor,
                             frame inputFrame: GPUFrame, scene: MetalScene,
                             lights: [MetalPunctualLight], draws: [Int], transforms: [DrawFrameTransform],
                             background: any MTLTexture,
                             samples: Int = 1, format: MTLPixelFormat = .rgba16Float,
                             wireframe: Bool = false, style: MetalDrawStyle = .shaded,
                             viewport: MTLViewport? = nil, animationPose: AnimationPose? = nil) throws {
        var frame = inputFrame
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw MetalRendererError.resource("render encoder") }
        if let viewport { encoder.setViewport(viewport) }
        encoder.setVertexBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        if wireframe { encoder.setTriangleFillMode(.lines) }
        environment?.bind(encoder)
        encoder.setFragmentTexture(background, index: 30)
        var gpuLights = lights.map(GPULight.init)
        if gpuLights.isEmpty { gpuLights = [GPULight.zero] }
        gpuLights.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 4) }
        // Wireframe-on-shaded: a second pass of edges over the shaded frame (`MetalDrawStyle`).
        let passes: [MetalDrawStyle] = style == .wireframeOnShaded ? [.shaded, .wireframeOnShaded] : [style]
        for passStyle in passes {
        if passStyle == .wireframeOnShaded { passStyle.configureEdgePass(encoder) }
        for index in draws {
            let draw = scene.draws[index]
            if passStyle == .wireframeOnShaded, !MetalDrawStyle.hasTriangles(draw) { continue }
            let source = passStyle.material(for: draw.material)
            let blend = passStyle.blends(source)
            let weights = scene.morphWeights(for: draw, pose: animationPose)
            let mask = Self.activeMorphMask(draw, weights: weights)
            encoder.setRenderPipelineState(try pipeline(blend: blend, samples: samples, format: format, morphMask: mask))
            encoder.setDepthStencilState(blend || passStyle == .wireframeOnShaded ? depthRead : depthWrite)
            let transform = frameTransform(transforms, index, draw)
            encoder.setCullMode(source.doubleSided || passStyle.drawsBackFaces ? .none : .back)
            encoder.setFrontFacing(transform.negativeScale ? .clockwise : .counterClockwise)
            var uniforms = GPUDraw(model: transform.model, normalMatrix: transform.normalMatrix, morphInfo: Self.morphInfo(draw, mask: mask))
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUDraw>.stride, index: 2)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUDraw>.stride, index: 2)
            var material = GPUMaterial(source)
            passStyle.adjust(&material)
            encoder.setFragmentBytes(&material, length: MemoryLayout<GPUMaterial>.stride, index: 3)
            encoder.setVertexBytes(&material, length: MemoryLayout<GPUMaterial>.stride, index: 3)
            let resourceKey = ObjectIdentifier(draw.vertexBuffer)
            if materialResources[resourceKey] == nil {
                materialResources[resourceKey] = try MetalMaterialResources(draw.material, device: device, library: library)
            }
            materialResources[resourceKey]?.bind(encoder)
            encoder.setVertexBuffer(draw.vertexBuffer, offset: 0, index: 0)
            Self.bindMorph(encoder, draw: draw, weights: weights, mask: mask, device: device)
            encoder.drawIndexedPrimitives(type: draw.primitiveType, indexCount: draw.indexCount, indexType: .uint32,
                                          indexBuffer: draw.indexBuffer, indexBufferOffset: 0)
        }
        }
        encoder.endEncoding()
    }

    private func encodePick(command: any MTLCommandBuffer, pass: MTLRenderPassDescriptor, frame inputFrame: GPUFrame,
                            scene: MetalScene, draws: [Int], transforms: [DrawFrameTransform], viewport: MTLViewport) throws {
        var frame = inputFrame
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw MetalRendererError.resource("pick encoder") }
        encoder.setViewport(viewport)
        encoder.setVertexBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        encoder.setFragmentBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        for drawIndex in draws {
            let draw = scene.draws[drawIndex]
            let blend = draw.material.alphaMode == 2
            let weights = scene.morphWeights(for: draw, pose: nil)
            let mask = Self.activeMorphMask(draw, weights: weights)
            encoder.setRenderPipelineState(try pickPipeline(morphMask: mask))
            encoder.setDepthStencilState(blend ? depthRead : depthWrite)
            let transform = frameTransform(transforms, drawIndex, draw)
            encoder.setCullMode(draw.material.doubleSided ? .none : .back)
            encoder.setFrontFacing(transform.negativeScale ? .clockwise : .counterClockwise)
            var uniforms = GPUDraw(model: transform.model, normalMatrix: transform.normalMatrix, morphInfo: Self.morphInfo(draw, mask: mask))
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
            var drawID = UInt32(drawIndex + 1)
            encoder.setFragmentBytes(&drawID, length: MemoryLayout<UInt32>.stride, index: 6)
            encoder.setVertexBuffer(draw.vertexBuffer, offset: 0, index: 0)
            Self.bindMorph(encoder, draw: draw, weights: weights, mask: mask, device: device)
            encoder.drawIndexedPrimitives(type: draw.primitiveType, indexCount: draw.indexCount, indexType: .uint32,
                                          indexBuffer: draw.indexBuffer, indexBufferOffset: 0)
        }
        encoder.endEncoding()
    }

    private func pickPipeline(morphMask: UInt32) throws -> any MTLRenderPipelineState {
        if let cached = pickPipelines[morphMask] { return cached }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try khronosVertex(morphMask: morphMask, capture: false)
        descriptor.fragmentFunction = library.makeFunction(name: "khronos_pick_fragment")
        descriptor.colorAttachments[0].pixelFormat = .r32Uint
        descriptor.depthAttachmentPixelFormat = .depth32Float
        let made = try device.makeRenderPipelineState(descriptor: descriptor)
        pickPipelines[morphMask] = made
        return made
    }

    private func pipeline(blend: Bool, samples: Int = 1, format: MTLPixelFormat = .rgba16Float, morphMask: UInt32 = 0) throws -> any MTLRenderPipelineState {
        let key = "\(blend)-\(samples)-\(format.rawValue)-m\(morphMask)"
        if let cached = pipelines[key] { return cached }
        let start = CFAbsoluteTimeGetCurrent()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try khronosVertex(morphMask: morphMask, capture: false)
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

    private func capturePipeline(morphMask: UInt32) throws -> any MTLRenderPipelineState {
        if let cached = capturePipelines[morphMask] { return cached }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = try khronosVertex(morphMask: morphMask, capture: true)
        descriptor.fragmentFunction = library.makeFunction(name: "khronos_capture_fragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        let made = try device.makeRenderPipelineState(descriptor: descriptor)
        capturePipelines[morphMask] = made
        return made
    }

    /// `morph_mask` 0, `morph_capture` 1, `morph_streams` 2. Streams exist only when the mask is nonzero,
    /// so a rigid draw's vertex function has the same resources as before morph.
    private func khronosVertex(morphMask: UInt32, capture: Bool) throws -> any MTLFunction {
        var mask = morphMask
        var captureFlag = capture
        var streams = morphMask != 0
        let values = MTLFunctionConstantValues()
        values.setConstantValue(&mask, type: .uint, index: 0)
        values.setConstantValue(&captureFlag, type: .bool, index: 1)
        values.setConstantValue(&streams, type: .bool, index: 2)
        return try library.makeFunction(name: "khronos_vertex", constantValues: values)
    }

    /// A zero weight vector uses the rigid pipeline. Capture forces the draw's mask so weight 0 still
    /// executes the shader's `position + 0·Δ` path.
    private static func activeMorphMask(_ draw: MetalDraw, weights: [Float], force: Bool = false) -> UInt32 {
        guard draw.morphBuffer != nil, draw.morphMask != 0 else { return 0 }
        if force || weights.contains(where: { $0 != 0 }) { return draw.morphMask }
        return 0
    }

    private static func morphInfo(_ draw: MetalDraw, mask: UInt32) -> SIMD4<UInt32> {
        SIMD4(UInt32(draw.morphTargetCount), UInt32(draw.morphVertexCount), mask, 0)
    }

    /// `setVertexBytes` is capped at 4 KB. A mesh with more weights than that gets a buffer.
    private static func bindMorph(_ encoder: any MTLRenderCommandEncoder, draw: MetalDraw, weights: [Float], mask: UInt32, device: any MTLDevice) {
        guard mask != 0, let morphBuffer = draw.morphBuffer, !weights.isEmpty else { return }
        encoder.setVertexBuffer(morphBuffer, offset: 0, index: 4)
        let byteCount = weights.count * MemoryLayout<Float>.stride
        if byteCount <= 4096 {
            weights.withUnsafeBytes { raw in
                encoder.setVertexBytes(raw.baseAddress!, length: byteCount, index: 5)
            }
        } else if let buffer = device.makeBuffer(bytes: weights, length: byteCount, options: .storageModeShared) {
            encoder.setVertexBuffer(buffer, offset: 0, index: 5)
        }
    }

    private func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int, _ usage: MTLTextureUsage,
                         storage: MTLStorageMode = .private) throws -> any MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = usage
        d.storageMode = storage
        guard let texture = device.makeTexture(descriptor: d) else { throw MetalRendererError.resource("texture \(format)") }
        return texture
    }

    /// Object-space vertices after the morph the shader would apply for `pose`.
    /// Points so every emitted vertex runs once; the write happens before the model transform.
    func captureMorphedVertices(drawIndex: Int, pose: AnimationPose?) throws -> [MetalVertex] {
        guard let scene else { throw MetalRendererError.noScene }
        guard scene.draws.indices.contains(drawIndex) else { throw MetalRendererError.resource("draw index") }
        let draw = scene.draws[drawIndex]
        let count = draw.vertexBuffer.length / MemoryLayout<MetalVertex>.stride
        guard count > 0 else { return [] }
        let weights = scene.morphWeights(for: draw, pose: pose)
        let mask = Self.activeMorphMask(draw, weights: weights, force: draw.morphTargetCount > 0)
        let byteCount = count * MemoryLayout<MetalVertex>.stride
        guard let captured = device.makeBuffer(length: byteCount, options: .storageModeShared) else {
            throw MetalRendererError.resource("morph capture")
        }
        memset(captured.contents(), 0, byteCount)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = try texture(.rgba8Unorm, 1, 1, [.renderTarget])
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .dontCare
        guard let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw MetalRendererError.resource("morph capture encoder")
        }
        encoder.setRenderPipelineState(try capturePipeline(morphMask: mask))
        var frame = GPUFrame(viewProjection: matrix_identity_float4x4, cameraPosition: .zero,
                             environment: .zero, options: .zero, viewport: SIMD4(1, 1, 0, 0))
        encoder.setVertexBytes(&frame, length: MemoryLayout<GPUFrame>.stride, index: 1)
        var uniforms = GPUDraw(model: matrix_identity_float4x4, normalMatrix: matrix_identity_float4x4,
                               morphInfo: Self.morphInfo(draw, mask: mask))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GPUDraw>.stride, index: 2)
        var material = GPUMaterial(draw.material)
        encoder.setVertexBytes(&material, length: MemoryLayout<GPUMaterial>.stride, index: 3)
        encoder.setVertexBuffer(draw.vertexBuffer, offset: 0, index: 0)
        Self.bindMorph(encoder, draw: draw, weights: weights, mask: mask, device: device)
        encoder.setVertexBuffer(captured, offset: 0, index: 6)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: count)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw MetalRendererError.gpu(error.localizedDescription) }
        let pointer = captured.contents().bindMemory(to: MetalVertex.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
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

    /// One `drawScene`. `models[i]` is the per-frame model of `draws[i]` (the rest world when no
    /// clip is active). The lists are re-sorted in place, as upstream does every frame.
    mutating func frame(draws: [MetalDraw], models: [simd_float4x4], view: simd_float4x4) -> Frame {
        var prepass: [Int]?
        var transparentDepths: [Float] = []
        if !transmission.isEmpty {
            (transparent, transparentDepths) = Self.sortedByDepth(transparent, draws: draws, models: models, view: view)
            prepass = opaque + transparent
        }
        let transmissionDepths: [Float]
        (transmission, transmissionDepths) = Self.sortedByDepth(transmission, draws: draws, models: models, view: view)
        (transparent, transparentDepths) = Self.sortedByDepth(transparent, draws: draws, models: models, view: view)
        // `filter((a) => a.depth <= 0)`: drawables whose centroid is behind the camera are skipped.
        let front = { (list: [Int], depths: [Float]) in zip(list, depths).filter { $0.1 <= 0 }.map(\.0) }
        return Frame(transmissionPrepass: prepass,
                     main: opaque + front(transmission, transmissionDepths) + front(transparent, transparentDepths))
    }

    mutating func frame(draws: [MetalDraw], view: simd_float4x4) -> Frame {
        frame(draws: draws, models: draws.map(\.worldTransform), view: view)
    }

    /// `Camera.sortPrimitivesByDepth`: the view-space Z of the primitive centroid, ascending
    /// (farthest first), with `Array.prototype.sort`'s stability.
    static func sortedByDepth(_ list: [Int], draws: [MetalDraw], models: [simd_float4x4], view: simd_float4x4) -> ([Int], [Float]) {
        var items = list.map { index in
            let model = models.indices.contains(index) ? models[index] : draws[index].worldTransform
            return (index, viewDepth(centroid: draws[index].centroid, model: model, view: view))
        }
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

    static func viewDepth(of draw: MetalDraw, view: simd_float4x4) -> Float {
        viewDepth(centroid: draw.centroid, model: draw.worldTransform, view: view)
    }

    /// gl-matrix `multiply(view, world)` then `transformMat4(centroid)`: double arithmetic,
    /// Float32 storage, divided by w (or 1 when w is 0). `model` is the per-frame world.
    static func viewDepth(centroid: SIMD3<Float>, model: simd_float4x4, view: simd_float4x4) -> Float {
        let world = model
        func modelView(_ column: Int, _ row: Int) -> Double {
            var sum = 0.0
            for k in 0..<4 { sum += Double(world[column][k]) * Double(view[k][row]) }
            return Double(Float(sum))
        }
        let x = Double(centroid.x), y = Double(centroid.y), z = Double(centroid.z)
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
private struct GPUDraw {
    var model: simd_float4x4
    var normalMatrix: simd_float4x4
    var morphInfo: SIMD4<UInt32>
}
private func toneMap(_ mapping: RenderLook.ToneMapping) -> UInt32 {
    switch mapping { case .pbrNeutral: 0; case .none: 1; case .acesNarkowicz: 2; case .acesHill: 3 }
}

/// `u_DebugOutput` in pbr.metal. Wireframe is a fill mode, not a channel.
private func debugOutput(_ mode: RenderViewMode) -> UInt32 {
    guard case .channel(let channel) = mode else { return 0 }
    return switch channel {
    case .baseColor: 1
    case .normals: 2
    case .metallic: 3
    case .roughness: 4
    case .tangents: 5
    case .textureCoordinates: 6
    case .ambientOcclusion: 7
    case .emissive: 8
    case .alpha: 9
    case .specular: 10
    case .clearcoat: 11
    case .clearcoatRoughness: 12
    case .clearcoatNormal: 13
    }
}
