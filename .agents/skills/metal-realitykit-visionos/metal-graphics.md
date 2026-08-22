# Metal GPU Programming Reference

> Read this when: Metal pipelines, buffers, textures (incl. IOSurface), shaders, dispatch, or frame pacing.

## Contents

- [Device & queue](#device--queue)
- [Compute pipeline](#compute-pipeline)
- [Render pipeline](#render-pipeline)
- [Buffers & textures](#buffers--textures)
- [Dispatch](#dispatch)
- [Shaders](#shaders)
- [Frame pacing](#frame-pacing)

## Device & queue

```swift
import Metal

guard let device = MTLCreateSystemDefaultDevice() else { fatalError("Metal unsupported") }
let commandQueue = device.makeCommandQueue()!

guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
defer { commandBuffer.commit() }
guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
// encode…
encoder.endEncoding()

commandBuffer.addCompletedHandler { buffer in
    if let error = buffer.error { print(error) }
}
```

## Compute pipeline

```swift
let library = device.makeDefaultLibrary()!
let function = library.makeFunction(name: "myKernel")!
let pipelineState = try device.makeComputePipelineState(function: function)

let constants = MTLFunctionConstantValues()
var useHQ = true
constants.setConstantValue(&useHQ, type: .bool, index: 0)
let specialized = try library.makeFunction(name: "myKernel", constantValues: constants)

let desc = MTLComputePipelineDescriptor()
desc.computeFunction = specialized
let archiveDesc = MTLBinaryArchiveDescriptor(); archiveDesc.url = cacheURL
let archive = try device.makeBinaryArchive(descriptor: archiveDesc)
desc.binaryArchives = [archive]
_ = try device.makeComputePipelineState(descriptor: desc, options: [], reflection: nil)
try archive.serialize(to: cacheURL)
```

## Render pipeline

```swift
let desc = MTLRenderPipelineDescriptor()
desc.vertexFunction = library.makeFunction(name: "vertexShader")
desc.fragmentFunction = library.makeFunction(name: "fragmentShader")
desc.colorAttachments[0].pixelFormat = .bgra8Unorm
desc.colorAttachments[0].isBlendingEnabled = true
desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
desc.depthAttachmentPixelFormat = .depth32Float

let vd = MTLVertexDescriptor()
vd.attributes[0].format = .float3; vd.attributes[0].offset = 0; vd.attributes[0].bufferIndex = 0
vd.attributes[1].format = .float2; vd.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride; vd.attributes[1].bufferIndex = 0
vd.layouts[0].stride = MemoryLayout<SIMD3<Float>>.stride + MemoryLayout<SIMD2<Float>>.stride
desc.vertexDescriptor = vd

let pipeline = try device.makeRenderPipelineState(descriptor: desc)

let pass = MTLRenderPassDescriptor()
pass.colorAttachments[0].texture = drawable.texture
pass.colorAttachments[0].loadAction = .clear
pass.colorAttachments[0].storeAction = .store
pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
pass.depthAttachment.texture = depthTexture
pass.depthAttachment.loadAction = .clear
pass.depthAttachment.clearDepth = 1.0

guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
enc.setRenderPipelineState(pipeline)
enc.endEncoding()
```

## Buffers & textures

```swift
let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: [])!
let empty = device.makeBuffer(length: stride * count, options: [])!
encoder.setVertexBuffer(buffer, offset: 0, index: 0)
// Triple-buffer: 3 MTLBuffers; advance write index after each commit
let pool = (0..<3).map { _ in device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: [])! }

let td = MTLTextureDescriptor()
td.pixelFormat = .rgba8Unorm; td.width = w; td.height = h
td.usage = [.shaderRead, .shaderWrite]; td.storageMode = .private
let texture = device.makeTexture(descriptor: td)!

import IOSurface
let surface = IOSurface(properties: [
    .width: w, .height: h, .bytesPerElement: 4,
    .bytesPerRow: w * 4, .allocSize: w * h * 4,
    .pixelFormat: kCVPixelFormatType_32BGRA
])!
let td2 = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
td2.usage = [.shaderRead, .renderTarget]; td2.storageMode = .shared
_ = device.makeTexture(descriptor: td2, iosurface: surface, plane: 0)!
surface.lock(options: [], seed: nil); defer { surface.unlock(options: [], seed: nil) }
```

## Dispatch

```swift
let maxT = pipelineState.maxTotalThreadsPerThreadgroup
let tw = pipelineState.threadExecutionWidth
let tgs = MTLSize(width: tw, height: maxT / tw, depth: 1)

encoder.setComputePipelineState(pipelineState)
encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(count, maxT), height: 1, depth: 1))
encoder.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: tgs)
```

## Shaders

```metal
#include <metal_stdlib>
using namespace metal;

constant bool useHighQuality [[function_constant(0)]];

kernel void processData(
    device float4 *input [[buffer(0)]],
    device float4 *output [[buffer(1)]],
    constant Uniforms &uniforms [[buffer(2)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= uniforms.elementCount) return;
    output[tid] = input[tid];
}

struct VertexIn { float3 position [[attribute(0)]]; float2 texCoord [[attribute(1)]]; };
struct VertexOut { float4 position [[position]]; float2 texCoord; };

vertex VertexOut vertexShader(VertexIn in [[stage_in]], constant float4x4 &mvp [[buffer(1)]]) {
    VertexOut o; o.position = mvp * float4(in.position, 1); o.texCoord = in.texCoord; return o;
}

fragment half4 fragmentShader(VertexOut in [[stage_in]], texture2d<half> tex [[texture(0)]], sampler s [[sampler(0)]]) {
    return tex.sample(s, in.texCoord);
}

kernel void reductionKernel(
    device float *input [[buffer(0)]], device float *output [[buffer(1)]],
    threadgroup float *shared [[threadgroup(0)]],
    uint tid [[thread_position_in_grid]], uint lid [[thread_position_in_threadgroup]],
    uint gSize [[threads_per_threadgroup]]
) {
    shared[lid] = input[tid];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint stride = gSize / 2; stride > 0; stride >>= 1) {
        if (lid < stride) shared[lid] += shared[lid + stride];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (lid == 0) output[tid / gSize] = shared[0];
}
```

| Swift | Metal |
|-------|-------|
| `SIMD2/3/4<Float>` | `float2/3/4` |
| `simd_float4x4` | `float4x4` |
| `UInt32` / `Float` / `Bool` | `uint` / `float` / `bool` |

## Frame pacing

`DispatchSemaphore` (max ~3): `wait()` before encode; `signal()` in `addCompletedHandler`. Keep CPU from racing ahead of GPU.
