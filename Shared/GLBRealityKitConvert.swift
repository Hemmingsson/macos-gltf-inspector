// Vendored from warrenm/GLTFKit2 GLTFRealityKit.swift (MIT).
// Packed accessor helpers live in GLBPackedAccessors.swift. Patched: sheen, transmission, POINTS, unnamed joints.

#if !os(tvOS)

import RealityKit
import Accelerate
import GLTFKit2
import simd
#if os(macOS)
import AppKit
#endif

#if os(macOS)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif

// Omit support for RealityKit entirely on platforms (such as macOS 11 Big Sur)
// that don't have the required API or language features from the RealityKit 2
// era.
// We would, of course, prefer to use a check that actually corresponds to the
// minimum supported SDKs (macOS 12 Monterey, iOS 15, etc.), but we lack the
// tools necessary to do so, so we fall back on compiler version.
// https://forums.swift.org/t/do-we-need-something-like-if-available/40349/34
#if compiler(>=5.6)


enum GLBTextureFilter {
    static func minMip(from filter: GLTFMinMipFilter) -> (MTLSamplerMinMagFilter, MTLSamplerMipFilter) {
        switch filter {
        case .linear:
            return (.linear, .notMipmapped)
        case .nearest:
            return (.nearest, .notMipmapped)
        case .nearestNearest:
            return (.nearest, .nearest)
        case .linearNearest:
            return (.linear, .nearest)
        case .nearestLinear:
            return (.nearest, .linear)
        default:
            return (.linear, .linear)
        }
    }

    static func mag(from filter: GLTFMagFilter) -> MTLSamplerMinMagFilter {
        switch filter {
        case .nearest:
            return .nearest
        default:
            return .linear
        }
    }

    static func addressMode(from addressMode: GLTFAddressMode) -> MTLSamplerAddressMode {
        switch addressMode {
        case .repeat:
            return .repeat
        case .mirroredRepeat:
            return .mirrorRepeat
        default:
            return .clampToEdge
        }
    }
}

extension MTLSamplerDescriptor {
    convenience init(from sampler: GLTFTextureSampler) {
        self.init()
        self.normalizedCoordinates = true
        let (minFilter, mipFilter) = GLBTextureFilter.minMip(from: sampler.minMipFilter)
        self.minFilter = minFilter
        self.mipFilter = mipFilter
        self.magFilter = GLBTextureFilter.mag(from: sampler.magFilter)
        self.sAddressMode = GLBTextureFilter.addressMode(from: sampler.wrapS)
        self.tAddressMode = GLBTextureFilter.addressMode(from: sampler.wrapT)
    }
}

fileprivate class UniqueNameGenerator {
    private var countsForPrefixes = [String : Int]()

    func nextUniqueName(prefix: String) -> String {
        if let existingCount = countsForPrefixes[prefix] {
            countsForPrefixes[prefix] = existingCount + 1
            return "\(prefix)\(existingCount + 1)"
        } else {
            countsForPrefixes[prefix] = 1
            return "\(prefix)1"
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
class GLBRealityKitResourceContext {
    enum ColorMask : Int {
        case red
        case green
        case blue
        case alpha
        case all

        var textureSwizzle: MTLTextureSwizzleChannels {
            switch self {
            case .red:
                return MTLTextureSwizzleChannels(red: .red, green: .red, blue: .red, alpha: .alpha)
            case .green:
                return MTLTextureSwizzleChannels(red: .green, green: .green, blue: .green, alpha: .alpha)
            case .blue:
                return MTLTextureSwizzleChannels(red: .blue, green: .blue, blue: .blue, alpha: .alpha)
            case .alpha:
                return MTLTextureSwizzleChannels(red: .alpha, green: .alpha, blue: .alpha, alpha: .alpha)
            case .all:
                return MTLTextureSwizzleChannels(red: .red, green: .green, blue: .blue, alpha: .alpha)
            }
        }
    }

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private var cgImagesForImageIdentifiers = [UUID : CGImage]()
    private var textureResourcesForImageIdentifiers = [UUID : [(RealityKit.TextureResource, ColorMask)]]()

    var defaultMaterial: any Material {
        return RealityKit.SimpleMaterial(color: .init(white: 0.5, alpha: 1.0), isMetallic: false)
    }

    init() {
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Unable to create Metal system default device")
        }
        self.device = metalDevice
        self.commandQueue = metalDevice.makeCommandQueue()!
    }

    @MainActor func alphaUsage(for gltfTextureParams: GLTFTextureParams) -> GLBTextureAlpha.Usage {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else {
            return .unused
        }
        var cgImage = cgImagesForImageIdentifiers[image.identifier]
        if cgImage == nil {
            cgImage = image.newCGImage()?.takeRetainedValue()
            if let cgImage {
                cgImagesForImageIdentifiers[image.identifier] = cgImage
            }
        }
        guard let cgImage, let range = GLBTextureAlpha.range(of: cgImage) else { return .unused }
        return GLBTextureAlpha.usage(minAlpha: range.0, maxAlpha: range.1)
    }

    @MainActor func cachedCGImage(for gltfTextureParams: GLTFTextureParams) -> CGImage? {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else {
            return nil
        }
        if let existing = cgImagesForImageIdentifiers[image.identifier] {
            return existing
        }
        let cgImage = image.newCGImage()?.takeRetainedValue()
        if let cgImage {
            cgImagesForImageIdentifiers[image.identifier] = cgImage
        }
        return cgImage
    }

    @MainActor func opacityTexture(for gltfTextureParams: GLTFTextureParams)
        -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        guard let cgImage = cachedCGImage(for: gltfTextureParams),
              let gray = GLBTextureAlpha.opacityMap(of: cgImage)
        else { return nil }
        let options = TextureResource.CreateOptions(semantic: .raw)
        guard let resource = try? TextureResource.generate(from: gray, options: options) else { return nil }
        let descriptor = MTLSamplerDescriptor(from: gltfTextureParams.texture.sampler ?? GLTFTextureSampler())
        return RealityKit.PhysicallyBasedMaterial.Texture(
            resource,
            sampler: MaterialParameters.Texture.Sampler(descriptor)
        )
    }

    @MainActor func texture(for gltfTextureParams: GLTFTextureParams, channels: ColorMask,
                            semantic: RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    {
        let gltfTexture = gltfTextureParams.texture
        guard let image = (gltfTexture.basisUSource ?? gltfTexture.webpSource ?? gltfTexture.source) else { return nil }
        if let resource = textureResource(for:image, channels: channels, semantic: semantic) {
            let descriptor = MTLSamplerDescriptor(from: gltfTexture.sampler ?? GLTFTextureSampler())
            let sampler = MaterialParameters.Texture.Sampler(descriptor)
            return RealityKit.PhysicallyBasedMaterial.Texture(resource, sampler: sampler)
        }
        return nil
    }

    @MainActor func textureResource(for gltfImage: GLTFImage, channels: ColorMask,
                                    semantic: RealityKit.TextureResource.Semantic) -> RealityKit.TextureResource?
    {
        let existingResources = textureResourcesForImageIdentifiers[gltfImage.identifier]
        if let existingMatch = existingResources?.first(where: { $0.1 == channels })?.0 {
            return existingMatch
        }

        #if compiler(>=6.0)
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
            if gltfImage.inferMediaType() == GLTFMediaTypeKTX2 {
                let mtlTexture = gltfImage.newTexture(with: device)
                guard let sourceTexture = mtlTexture else { return nil }
                do {
                    let lowLevelDesc = LowLevelTexture.Descriptor(textureType: sourceTexture.textureType,
                                                                  pixelFormat: sourceTexture.pixelFormat,
                                                                  width: sourceTexture.width,
                                                                  height: sourceTexture.height,
                                                                  depth: sourceTexture.depth,
                                                                  mipmapLevelCount: sourceTexture.mipmapLevelCount,
                                                                  arrayLength: sourceTexture.arrayLength,
                                                                  textureUsage: [.shaderRead],
                                                                  swizzle: channels.textureSwizzle)
                    let lowLevelTexture = try LowLevelTexture(descriptor: lowLevelDesc)
                    if let commandBuffer = commandQueue.makeCommandBuffer() {
                        let targetTexture = lowLevelTexture.replace(using: commandBuffer)
                        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                            blitEncoder.copy(from: sourceTexture, to: targetTexture)
                            blitEncoder.endEncoding()
                        }
                        commandBuffer.commit()
                    }
                    let resource = try TextureResource(from: lowLevelTexture)
                    if textureResourcesForImageIdentifiers[gltfImage.identifier] != nil {
                        textureResourcesForImageIdentifiers[gltfImage.identifier]!.append((resource, channels))
                    } else {
                        textureResourcesForImageIdentifiers[gltfImage.identifier] = [(resource, channels)]
                    }
                    return resource
                } catch {
                    GLBLog.error(GLBLog.load, "KTX2 texture convert failed: \(error)")
                    return nil
                }
            }
        }
        #endif

        var cgImage = cgImagesForImageIdentifiers[gltfImage.identifier]
        if cgImage == nil {
            cgImage = gltfImage.newCGImage()?.takeRetainedValue()
            if cgImage != nil {
                #if os(visionOS)
                // Image decoding is not as robust on visionOS as on other platforms,
                // so we "pre-decode" here into a known-good image layout.
                cgImage = decodeCGImage(cgImage!)
                #endif
                cgImagesForImageIdentifiers[gltfImage.identifier] = cgImage
            }
        }
        guard let originalImage = cgImage else { return nil }

        guard let sourceImage = (channels == .all) ? originalImage :
                singleChannelImage(from: originalImage, channels: channels) else { return nil }

        let options = TextureResource.CreateOptions(semantic: semantic)
        guard let resource = try? TextureResource.generate(from: sourceImage, options: options) else { return nil }
        if textureResourcesForImageIdentifiers[gltfImage.identifier] != nil {
            textureResourcesForImageIdentifiers[gltfImage.identifier]!.append((resource, channels))
        } else {
            textureResourcesForImageIdentifiers[gltfImage.identifier] = [(resource, channels)]
        }

        return resource
    }

    func singleChannelImage(from cgImage: CGImage, channels: ColorMask) -> CGImage? {
        guard (cgImage.colorSpace?.model == .rgb) else {
            // Can't extract from a non-RGB[A] image with this method. Fall back to the input image hoping it's monochrome.
            return cgImage
        }
        // PNG on macOS is usually BGRA. `vImageExtractChannel_ARGB8888` only
        // matches after we convert; RealityKit then samples the gray as red.
        guard let argbFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            renderingIntent: .defaultIntent
        ) else { return nil }
        guard var inputBuffer = try? vImage_Buffer(cgImage: cgImage, format: argbFormat) else { return nil }
        defer { inputBuffer.free() }
        var outputBuffer = vImage_Buffer()
        vImageBuffer_Init(&outputBuffer, inputBuffer.height, inputBuffer.width, 8, vImage_Flags())
        defer { outputBuffer.data.deallocate() }
        // ARGB8888: 0=A, 1=R, 2=G, 3=B
        let channel: Int
        switch channels {
        case .red: channel = 1
        case .green: channel = 2
        case .blue: channel = 3
        case .alpha: channel = 0
        case .all: return nil
        }
        let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
        let outputFormat = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 8, colorSpace: outputColorSpace,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                                renderingIntent: .defaultIntent)!
        vImageExtractChannel_ARGB8888(&inputBuffer, &outputBuffer, channel, vImage_Flags())
        let outputImage = try? outputBuffer.createCGImage(format: outputFormat)
        return outputImage
    }

    func decodeCGImage(_ image: CGImage) -> CGImage? {
        let isSingleChannel = (image.colorSpace?.model == .monochrome)
        let wantsAlpha = ![CGImageAlphaInfo.none, CGImageAlphaInfo.noneSkipLast, CGImageAlphaInfo.noneSkipFirst].contains(image.alphaInfo)
        let bitsPerComponent = 8
        let width = image.width, height = image.height
        let bytesPerPixel = isSingleChannel ? 1 : 4
        let bytesPerRow = bytesPerPixel * width
        let colorSpace = CGColorSpace(name: isSingleChannel ? CGColorSpace.genericGrayGamma2_2 : CGColorSpace.sRGB)!
        var bitmapInfo: UInt32 = 0
        if (wantsAlpha) {
            if (image.alphaInfo == .alphaOnly) {
                bitmapInfo |= image.alphaInfo.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.premultipliedLast.rawValue
            }
        } else {
            if (isSingleChannel) {
                bitmapInfo |= CGImageAlphaInfo.none.rawValue
            } else {
                bitmapInfo |= CGImageAlphaInfo.noneSkipLast.rawValue
            }
        }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), byTiling: false)
        let image = context.makeImage()
        return image
    }
}

@available(macOS 12.0, iOS 15.0, *)
extension GLTFNode {
    var bindPath: BindTarget.EntityPath {
        if let parent = self.parent {
            return parent.bindPath.entity(self.name ?? "")
        }
        return BindTarget.entity(self.name ?? "")
    }
}

@available(macOS 12.0, iOS 15.0, *)
public class GLBRealityKitConvert {

#if os(macOS)
    let colorSpace = NSColorSpace(cgColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!)!
#endif
    private let nameGenerator = UniqueNameGenerator()

    private var pathsForSkeletonIDs: [/*MeshResource.Skeleton.ID*/String : BindTarget.EntityPath] = [:]
    private var skeletonIDsByJointName: [String: [/*MeshResource.Skeleton.ID*/String]] = [:]
    private var skeletonTransformsByJointName : [String: Transform] = [:]
    private var sourceAsset: GLTFAsset?
    private var ignoreBakedEmissive = false

    @MainActor static func convert(
        scene: GLTFScene,
        asset: GLTFAsset?,
        document: inout GLTFSessionDocument
    ) -> RealityKit.Entity {
        let instance = GLBRealityKitConvert()
        return instance.convert(scene: scene, asset: asset, document: &document)
    }

    @MainActor func convert(
        scene: GLTFScene,
        asset: GLTFAsset? = nil,
        document: inout GLTFSessionDocument
    ) -> RealityKit.Entity {
        sourceAsset = asset
        if let asset {
            document = Self.makeDocument(from: asset)
        }
        let emissiveHints = (asset?.materials ?? []).map(GLBPreviewEmissive.hint(from:))
        ignoreBakedEmissive = GLBPreviewEmissive.fileLooksBaked(emissiveHints)
        if ignoreBakedEmissive {
            GLBLog.info(GLBLog.lighting, "ignoring achromatic emissive boost; studio IBL already lights the model")
        }
        let context = GLBRealityKitResourceContext()

        let rootEntity = Entity()
        rootEntity.name = "glTF_\(scene.name ?? "Scene")_Root"

        do {
            let rootNodes = try scene.nodes.compactMap { try self.convert(node: $0, context: context) }

            for rootNode in rootNodes {
                rootEntity.addChild(rootNode)
            }
        } catch {
            GLBLog.error(GLBLog.load, "Error when converting scene: \(error)")
        }

        // TODO: Morph targets

        if #available(macOS 14.0, iOS 17.0, visionOS 2.0, *) {
            for animation in asset?.animations ?? [] {
                let rkAnimation = try? convert(animation: animation)
                rkAnimation?.store(in: rootEntity)
            }
        }

        return rootEntity
    }

    @MainActor func convert(node gltfNode: GLTFNode, context: GLBRealityKitResourceContext) throws -> RealityKit.Entity {
        let nodeEntity = ModelEntity()

        // TODO: This only ensures uniqueness for unnamed nodes; the asset could still contain duplicate names.
        nodeEntity.name = gltfNode.name ?? nameGenerator.nextUniqueName(prefix: "Node")
        nodeEntity.components.set(GLTFNodeIDComponent(nodeIndex: nodeIndex(of: gltfNode)))

        nodeEntity.transform = Transform(matrix: gltfNode.matrix)

        var skeleton: Any?
        #if compiler(>=6.0)
        if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
            if let skin = gltfNode.skin {
                if let meshSkeleton = convert(skin: skin) {
                    skeleton = meshSkeleton
                    // Cache some associations between joints, entities, and skeletons so we can look them up later.
                    pathsForSkeletonIDs[meshSkeleton.id] = gltfNode.bindPath
                    for joint in meshSkeleton.joints {
                        if joint.parentIndex == nil, let referenceNode = skin.skeleton {
                            // TODO: Calculate the total transformation between the joint and the skeleton node?
                            skeletonTransformsByJointName[joint.name] = Transform(matrix: referenceNode.matrix)
                        }
                        if let existingJointCache = skeletonIDsByJointName[joint.name] {
                            skeletonIDsByJointName[joint.name] = existingJointCache + [meshSkeleton.id]
                        } else {
                            skeletonIDsByJointName[joint.name] = [meshSkeleton.id]
                        }
                    }
                }
            }
        }
        #endif

        if let gltfMesh = gltfNode.mesh,
           let meshComponent = try convert(mesh: gltfMesh, skeleton: skeleton, context: context) {
            nodeEntity.components.set(meshComponent)
        }

        if #available(visionOS 2.0, *) {
            if let gltfLight = gltfNode.light {
                switch gltfLight.type {
                case .directional:
                    nodeEntity.components.set(convert(directionalLight: gltfLight))
                case .point:
                    nodeEntity.components.set(convert(pointLight: gltfLight))
                case .spot:
                    nodeEntity.components.set(convert(spotLight: gltfLight))
                default:
                    break
                }
            }
        }

        if let gltfCamera = gltfNode.camera, let cameraComponent = convert(camera: gltfCamera) {
            nodeEntity.components.set(cameraComponent)
        }

        for childNode in gltfNode.childNodes {
            nodeEntity.addChild(try convert(node: childNode, context: context))
        }

        return nodeEntity
    }

    #if compiler(>=6.0) || os(visionOS)
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
    func convert(skin gltfSkin: GLTFSkin) -> MeshResource.Skeleton? {
        let skeletonName = gltfSkin.name ?? nameGenerator.nextUniqueName(prefix: "Skin")
        let jointNames = gltfSkin.joints.enumerated().map { index, joint in
            GLBSkin.resolvedName(joint.name, index: index)
        }

        let jointParents = gltfSkin.joints.map { skeletonNode in
            if let parent = skeletonNode.parent {
                return gltfSkin.joints.firstIndex(of: parent)
            } else {
                return nil
            }
        }

        let ibmMatrices = {
            if let ibmAccessor = gltfSkin.inverseBindMatrices, let matrices = GLBPacked.float4x4(for: ibmAccessor) {
                return matrices
            } else {
                return [simd_float4x4](repeating: matrix_identity_float4x4, count: jointNames.count)
            }
        }()

        return MeshResource.Skeleton(id: skeletonName, jointNames: jointNames,
                                     inverseBindPoseMatrices: ibmMatrices, parentIndices: jointParents)
    }
    #endif

    @MainActor func convert(mesh gltfMesh: GLTFMesh, skeleton: Any? /*MeshResource.Skeleton?*/ = nil,
                            context: GLBRealityKitResourceContext) throws -> RealityKit.ModelComponent?
    {
        var skeletonID: String?
        #if compiler(>=6.0) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, *) {
            if let skeleton = skeleton as? MeshResource.Skeleton {
                skeletonID = skeleton.id
            }
        }
        #endif

        typealias PartMaterialPair = (MeshResource.Part, any RealityKit.Material)
        var primitiveMaterialIndex: Int = 0
        let partsAndMaterials = try gltfMesh.primitives.compactMap { primitive -> PartMaterialPair? in
            if let part = self.convert(primitive: primitive, materialIndex: primitiveMaterialIndex,
                                       skeletonID: skeletonID)
            {
                let material = try self.convert(material: primitive.material, context: context)
                primitiveMaterialIndex += 1
                return (part, material)
            }
            // If we fail to create a part from a primitive, omit it from the list.
            return nil
        }

        if partsAndMaterials.count == 0 {
            // If we weren't able to successfully build any parts for our primitives, don't bother generating a mesh.
            return nil
        }

        let parts = partsAndMaterials.map { $0.0 }
        let materials = partsAndMaterials.map { $0.1 }
        
        // TODO: This only ensures uniqueness for unnamed meshes; the asset could still contain duplicate names.
        let modelName = gltfMesh.name ?? nameGenerator.nextUniqueName(prefix: "Mesh")
        let model = MeshResource.Model(id: modelName, parts: parts)

        var meshContents = MeshResource.Contents()
        meshContents.models = MeshModelCollection([model])
        #if compiler(>=6.0) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, *) {
            if let skeleton = skeleton as? MeshResource.Skeleton {
                meshContents.skeletons = MeshSkeletonCollection([skeleton])
            }
        }
        #endif

        let meshResource = try MeshResource.generate(from: meshContents)
        let modelComponent = ModelComponent(mesh: meshResource, materials: materials)

        return modelComponent
    }

    func convertPoints(_ gltfPrimitive: GLTFPrimitive, materialIndex: Int) -> RealityKit.MeshResource.Part?
    {
        guard let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
              let points = GLBPacked.float3Array(for: positionAttribute.accessor),
              !points.isEmpty
        else { return nil }
        var minBound = points[0]
        var maxBound = points[0]
        for point in points {
            minBound = simd_min(minBound, point)
            maxBound = simd_max(maxBound, point)
        }
        let size = max(0.0005, simd_length(maxBound - minBound) * 0.004)
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(points.count * 3)
        indices.reserveCapacity(points.count * 3)
        for point in points {
            let base = UInt32(positions.count)
            positions.append(point + SIMD3(size, 0, 0))
            positions.append(point + SIMD3(0, size, 0))
            positions.append(point + SIMD3(0, 0, size))
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        let partName = nameGenerator.nextUniqueName(prefix: "Points")
        var part = MeshResource.Part(id: partName, materialIndex: materialIndex)
        part[MeshBuffers.positions] = MeshBuffers.Positions(positions)
        part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        return part
    }

    func convert(primitive gltfPrimitive: GLTFPrimitive, materialIndex: Int = 0, skeletonID: String? = nil)
        -> RealityKit.MeshResource.Part?
    {
        switch gltfPrimitive.primitiveType {
        case .points:
            return convertPoints(gltfPrimitive, materialIndex: materialIndex)
        case .triangles:
            break
        default:
            return nil
        }

        let partName = nameGenerator.nextUniqueName(prefix: "Primitive")
        var part = MeshResource.Part(id: partName, materialIndex: materialIndex)

        if let positionAttribute = gltfPrimitive.attribute(forName: "POSITION"),
           let positionArray = GLBPacked.float3Array(for: positionAttribute.accessor)
        {
            part[MeshBuffers.positions] = MeshBuffers.Positions(positionArray)
        }

        if let normalAttribute = gltfPrimitive.attribute(forName: "NORMAL"),
           let normalArray = GLBPacked.float3Array(for: normalAttribute.accessor)
        {
            part[MeshBuffers.normals] = MeshBuffers.Normals(normalArray)
        }

        if let tangentAttribute = gltfPrimitive.attribute(forName: "TANGENT"),
           let tangentArray = GLBPacked.float3Array(for: tangentAttribute.accessor)
        {
            part[MeshBuffers.tangents] = MeshBuffers.Tangents(tangentArray)
        }

        if let texCoordsArray = bakedTextureCoordinates(for: gltfPrimitive) {
            part[MeshBuffers.textureCoordinates] = MeshBuffers.TextureCoordinates(texCoordsArray)
        }

        #if compiler(>=6.0) || os(visionOS)
        if #available(macOS 15.0, iOS 18.0, *) {
            if let joints0Attribute = gltfPrimitive.attribute(forName: "JOINTS_0"),
               let weights0Attribute = gltfPrimitive.attribute(forName: "WEIGHTS_0"),
               let jointsArray = GLBPacked.ushort4Array(for: joints0Attribute.accessor),
               let weightsArray = GLBPacked.float4Array(for: weights0Attribute.accessor)
            {
                let weightsPerVertex = 4
                func jointInfluences(forJoints joints: [SIMD4<UInt16>], weights: [SIMD4<Float>]) -> [MeshJointInfluence] {
                    return zip(joints, weights).reduce(into: [MeshJointInfluence]()) { partialResult, jointsAndWeights in
                        let joints = jointsAndWeights.0; let weights = jointsAndWeights.1
                        partialResult.append(MeshJointInfluence(jointIndex: Int(joints[0]), weight: weights[0]))
                        partialResult.append(MeshJointInfluence(jointIndex: Int(joints[1]), weight: weights[1]))
                        partialResult.append(MeshJointInfluence(jointIndex: Int(joints[2]), weight: weights[2]))
                        partialResult.append(MeshJointInfluence(jointIndex: Int(joints[3]), weight: weights[3]))
                    }
                }

                let influences = jointInfluences(forJoints: jointsArray, weights: weightsArray)
                part.jointInfluences = MeshResource.JointInfluences(influences: MeshBuffers.JointInfluences(influences),
                                                                    influencesPerVertex: weightsPerVertex)
                part.skeletonID = skeletonID
            }
        }
        #endif

        // TODO: Support explicit bitangents and other user attributes?

        if let indexAccessor = gltfPrimitive.indices, let indices = GLBPacked.uint32Array(for: indexAccessor) {
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        } else {
            let vertexCount = gltfPrimitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            let indices = [UInt32](UInt32(0)..<UInt32(vertexCount))
            part.triangleIndices = MeshBuffers.TriangleIndices(indices)
        }

        return part
    }

    @MainActor func convert(material gltfMaterial: GLTFMaterial?,
                            context: GLBRealityKitResourceContext) throws -> any RealityKit.Material
    {
        guard let gltfMaterial = gltfMaterial else { return context.defaultMaterial }

        if gltfMaterial.isUnlit {
            var material = UnlitMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.color.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.color.texture = context.texture(for: baseColorTexture, channels: .all, semantic: .color)
                }
            }
            applyBlendMode(toUnlit: &material, gltfMaterial: gltfMaterial, context: context)
            return material
        } else {
            var material = PhysicallyBasedMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.baseColor.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.baseColor.texture = context.texture(for: baseColorTexture,
                                                                 channels: .all,
                                                                 semantic: .color)
                }
                material.roughness.scale = metallicRoughness.roughnessFactor
                material.metallic.scale = metallicRoughness.metallicFactor
                if let metallicRoughnessTexture = metallicRoughness.metallicRoughnessTexture {
                    material.roughness.texture = context.texture(for: metallicRoughnessTexture,
                                                                 channels: .green,
                                                                 semantic: .scalar)
                    material.metallic.texture = context.texture(for: metallicRoughnessTexture,
                                                                channels: .blue,
                                                                semantic: .scalar)
                }
            }
            if let specular = gltfMaterial.specular {
                var spec = PhysicallyBasedMaterial.Specular(scale: specular.specularFactor)
                if let specularTexture = specular.specularTexture {
                    spec.texture = context.texture(for: specularTexture, channels: .alpha, semantic: .scalar)
                }
                material.specular = spec
            } else {
                material.specular = .init(floatLiteral: 0)
            }
            if let normal = gltfMaterial.normalTexture, abs(normal.scale) > 0.0001 {
                material.normal.texture = context.texture(for: normal, channels: .all, semantic: .normal)
            }
            if let emissive = gltfMaterial.emissive {
                let hint = GLBPreviewEmissive.hint(from: gltfMaterial)
                if !GLBPreviewEmissive.shouldIgnore(hint, fileLooksBaked: ignoreBakedEmissive) {
                    var emissiveTexture: PhysicallyBasedMaterial.Texture?
                    if let texture = emissive.emissiveTexture {
                        emissiveTexture = context.texture(for: texture, channels: .all, semantic: .color)
                    }
                    material.emissiveColor = .init(
                        color: platformColor(for: simd_make_float4(emissive.emissiveFactor, 1)),
                        texture: emissiveTexture
                    )
                    material.emissiveIntensity = emissive.emissiveStrength
                }
            }
            if let occlusion = gltfMaterial.occlusionTexture {
                material.ambientOcclusion.texture = context.texture(for: occlusion, channels: .red, semantic: .scalar)
            }
            if let clearcoat = gltfMaterial.clearcoat {
                material.clearcoat.scale = clearcoat.clearcoatFactor
                if let clearcoatTexture = clearcoat.clearcoatTexture {
                    material.clearcoat.texture = context.texture(for: clearcoatTexture, channels: .red, semantic: .raw)
                }
                material.clearcoatRoughness.scale = clearcoat.clearcoatRoughnessFactor
                if let clearcoatRoughnessTexture = clearcoat.clearcoatRoughnessTexture {
                    material.clearcoatRoughness.texture = context.texture(for: clearcoatRoughnessTexture,
                                                                          channels: .green,
                                                                          semantic: .raw)
                }
                if #available(macOS 15.0, iOS 18.0, *) {
                    if let clearcoatNormalTexture = clearcoat.clearcoatNormalTexture {
                        material.clearcoatNormal = .init(
                            texture: context.texture(for: clearcoatNormalTexture, channels: .all, semantic: .normal)
                        )
                    }
                }
            }
            applyBlendMode(toPBR: &material, gltfMaterial: gltfMaterial, context: context)
            material.faceCulling = gltfMaterial.isDoubleSided ? .none : .back

            if let sheen = gltfMaterial.sheen {
                let color = sheen.sheenColorFactor
                var sheenColor = PhysicallyBasedMaterial.SheenColor(
                    tint: platformColor(for: simd_make_float4(color, 1.0))
                )
                if let sheenTexture = sheen.sheenColorTexture {
                    sheenColor.texture = context.texture(for: sheenTexture, channels: .all, semantic: .color)
                }
                material.sheen = sheenColor
            }
            if let transmission = gltfMaterial.transmission, transmission.transmissionFactor > 0 {
                let opacity = min(1, max(0.08, 1 - transmission.transmissionFactor))
                material.blending = .transparent(opacity: .init(scale: opacity))
            }
            return material
        }
    }

    @MainActor
    func applyBlendMode(
        toPBR material: inout PhysicallyBasedMaterial,
        gltfMaterial: GLTFMaterial,
        context: GLBRealityKitResourceContext
    ) {
        if gltfMaterial.alphaMode == .mask {
            material.opacityThreshold = gltfMaterial.alphaCutoff
            return
        }
        guard gltfMaterial.alphaMode == .blend else { return }
        let alpha = gltfMaterial.metallicRoughness?.baseColorFactor.w ?? 1
        if alpha < 0.999 {
            var opacity = PhysicallyBasedMaterial.Opacity(scale: alpha)
            if let texture = gltfMaterial.metallicRoughness?.baseColorTexture {
                opacity.texture = context.texture(for: texture, channels: .alpha, semantic: .scalar)
            }
            material.blending = .transparent(opacity: opacity)
            return
        }
        // Factor 1 + BLEND + empty/zero texture alpha is Sketchfab car paint (invisible
        // if blended). Factor 1 + BLEND + a real alpha span is foliage / decals.
        if let texture = gltfMaterial.metallicRoughness?.baseColorTexture,
           context.alphaUsage(for: texture) == .cutout
        {
            let opacity = context.opacityTexture(for: texture)
            material.blending = .transparent(opacity: .init(scale: 1, texture: opacity))
            material.opacityThreshold = 0.4
            return
        }
        material.blending = .opaque
    }

    @MainActor
    func applyBlendMode(
        toUnlit material: inout UnlitMaterial,
        gltfMaterial: GLTFMaterial,
        context: GLBRealityKitResourceContext
    ) {
        if gltfMaterial.alphaMode == .mask {
            material.opacityThreshold = gltfMaterial.alphaCutoff
            return
        }
        guard gltfMaterial.alphaMode == .blend else { return }
        let alpha = gltfMaterial.metallicRoughness?.baseColorFactor.w ?? 1
        if alpha < 0.999 {
            material.blending = .transparent(opacity: 1.0)
            return
        }
        if let texture = gltfMaterial.metallicRoughness?.baseColorTexture,
           context.alphaUsage(for: texture) == .cutout
        {
            if let opacity = context.opacityTexture(for: texture) {
                material.blending = .transparent(opacity: .init(scale: 1, texture: opacity))
            }
            material.opacityThreshold = 0.4
            return
        }
        material.blending = .opaque
    }

    /// Bake `KHR_texture_transform` in glTF space (`T * R * S`), then flip V for RealityKit.
    private func bakedTextureCoordinates(for primitive: GLTFPrimitive) -> [SIMD2<Float>]? {
        let params = primitive.material?.metallicRoughness?.baseColorTexture
            ?? primitive.material?.normalTexture
        let texCoord: Int
        if let transform = params?.transform, transform.hasTexCoord {
            texCoord = Int(transform.texCoord)
        } else {
            texCoord = params?.texCoord ?? 0
        }
        let attribute = primitive.attribute(forName: "TEXCOORD_\(texCoord)")
            ?? primitive.attribute(forName: "TEXCOORD_0")
        guard let attribute,
              var uvs = GLBPacked.float2Array(for: attribute.accessor, flipVertically: false)
        else { return nil }
        if let transform = params?.transform {
            let matrix = transform.matrix
            uvs = uvs.map { uv in
                let p = matrix * SIMD4(uv.x, uv.y, 0, 1)
                return SIMD2(p.x, p.y)
            }
        }
        return uvs.map { SIMD2($0.x, 1 - $0.y) }
    }

    @available(macOS 12.0, iOS 15.0, visionOS 2.0, *)
    func convert(spotLight gltfLight: GLTFLight) -> SpotLightComponent {
        let light = SpotLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                       intensity: gltfLight.intensity * 4 * .pi,
                                       innerAngleInDegrees: GLTFDegFromRad(gltfLight.innerConeAngle),
                                       outerAngleInDegrees: GLTFDegFromRad(gltfLight.outerConeAngle),
                                       attenuationRadius: punctualAttenuationRadius(gltfLight.range))
        return light
    }

    @available(macOS 12.0, iOS 15.0, visionOS 2.0, *)
    func convert(pointLight gltfLight: GLTFLight) -> PointLightComponent {
        let light = PointLightComponent(color:platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                        intensity: gltfLight.intensity * 4 * .pi,
                                        attenuationRadius: punctualAttenuationRadius(gltfLight.range))
        return light
    }

    @available(macOS 12.0, iOS 15.0, visionOS 2.0, *)
    func convert(directionalLight gltfLight: GLTFLight) -> DirectionalLightComponent {
        #if os(visionOS)
        let light = DirectionalLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                              intensity: gltfLight.intensity)
        #else
        let light = DirectionalLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                              intensity: gltfLight.intensity,
                                              isRealWorldProxy: false)
        #endif
        return light
    }

    /// glTF `range <= 0` means infinite; RealityKit rejects a zero radius.
    private func punctualAttenuationRadius(_ range: Float) -> Float {
        range > 0 ? range : 1_000_000
    }

    func convert(camera: GLTFCamera) -> (any Component)? {
        if let perspectiveParams = camera.perspective {
            return PerspectiveCameraComponent(near: camera.zNear,
                                              far: camera.zFar,
                                              fieldOfViewInDegrees: GLTFDegFromRad(perspectiveParams.yFOV))
        }
        if let orthographicParams = camera.orthographic {
            if #available(macOS 15.0, iOS 18.0, visionOS 2.0, *) {
                var orthographic = OrthographicCameraComponent()
                orthographic.near = camera.zNear
                orthographic.far = camera.zFar
                orthographic.scale = orthographicParams.yMag
                return orthographic
            }
        }
        return nil
    }

    func convert(animation: GLTFAnimation) throws -> AnimationResource {
        let groupedChannels = animation.channels.reduce(into: [UUID : [GLTFAnimationChannel]]()) { partialResult, channel in
            guard let targetIdentifier = channel.target.node?.identifier else { return }
            if let _ = partialResult[targetIdentifier] {
                partialResult[targetIdentifier]! += [channel]
            } else {
                partialResult[targetIdentifier] = [channel]
            }
        }
        let name = animation.name ?? nameGenerator.nextUniqueName(prefix: "Animation")

        struct AnimatedJointData {
            var jointNames = [String]()
            var jointTransformSamplers = [GLBTransformSampler]()
            var minTime: Float = 0
            var maxTime: Float = 0
            var sampleInterval: Float = 1 / 30.0
        }
        var jointAnimation = AnimatedJointData()
        var animations = [AnimationDefinition]()
        for (_, channels) in groupedChannels {
            if let _ = channels.first(where: { $0.target.path == GLTFAnimationPath.weights.rawValue }), channels.count == 1 {
                continue // TODO: Implement morph target animation
            }
            guard let targetNode = channels.first?.target.node else {
                continue // Can't create an animation without at least one channel and a target
            }
            let translationChannel = channels.first { $0.target.path == GLTFAnimationPath.translation.rawValue }
            let rotationChannel = channels.first { $0.target.path == GLTFAnimationPath.rotation.rawValue }
            let scaleChannel = channels.first { $0.target.path == GLTFAnimationPath.scale.rawValue }
            let transformSampler = GLBTransformSampler(target: targetNode,
                                                        translationChannel: translationChannel,
                                                        rotationChannel: rotationChannel,
                                                        scaleChannel: scaleChannel,
                                                        maximumSampleInterval: 1 / 30.0) // TODO: Make sample interval an option
            if targetNode.isJoint {
                let jointName: String
                if let name = targetNode.name, !name.isEmpty {
                    jointName = name
                } else if let index = GLBSkin.jointIndex(of: targetNode, in: sourceAsset?.skins ?? []) {
                    jointName = GLBSkin.synthesizedName(index: index)
                } else {
                    jointName = nameGenerator.nextUniqueName(prefix: "joint")
                }
                jointAnimation.jointNames.append(jointName)
                jointAnimation.jointTransformSamplers.append(transformSampler)
                jointAnimation.minTime = min(jointAnimation.minTime, transformSampler.startTime)
                jointAnimation.maxTime = max(jointAnimation.maxTime, transformSampler.endTime)
                jointAnimation.sampleInterval = min(jointAnimation.sampleInterval, transformSampler.recommendedSampleInterval)
            } else {
                let frames = stride(from: transformSampler.startTime,
                                    through: transformSampler.endTime,
                                    by: transformSampler.recommendedSampleInterval).map
                {
                    transformSampler.transform(at: $0)
                }
                let sampledAnimation = SampledAnimation(frames: frames,
                                                        tweenMode: transformSampler.hasStepChannel ? .hold : .linear,
                                                        frameInterval: transformSampler.recommendedSampleInterval,
                                                        bindTarget: targetNode.bindPath.transform,
                                                        delay: TimeInterval(transformSampler.startTime))
                animations.append(sampledAnimation)
            }
        }
        if !jointAnimation.jointNames.isEmpty {
            var jointTransforms = [JointTransforms]()
            for t in stride(from: jointAnimation.minTime, through: jointAnimation.maxTime, by: jointAnimation.sampleInterval) {
                let sampledTransforms = zip(jointAnimation.jointNames, jointAnimation.jointTransformSamplers).map { jointName, transformSampler -> Transform in
                    var jointTransform = transformSampler.transform(at: t)
                    if let ancestorTransform = skeletonTransformsByJointName[jointName] {
                        jointTransform = Transform(matrix: ancestorTransform.matrix * jointTransform.matrix)
                    }
                    return jointTransform
                }
                jointTransforms.append(JointTransforms(sampledTransforms))
            }
            let delay = TimeInterval(jointAnimation.minTime)

            var animatedSkeletonIDs = Set</*MeshResource.Skeleton.ID*/String>()
            for jointName in jointAnimation.jointNames {
                if let skeletonIDs = skeletonIDsByJointName[jointName] {
                    animatedSkeletonIDs.formUnion(skeletonIDs)
                }
            }
            let animatedBindPaths = animatedSkeletonIDs.compactMap { pathsForSkeletonIDs[$0] }
            for bindPath in animatedBindPaths {
                let skeletalAnimation = SampledAnimation(jointNames: jointAnimation.jointNames,
                                                         frames: jointTransforms,
                                                         tweenMode: .linear, // TODO: Support .hold?
                                                         frameInterval: jointAnimation.sampleInterval,
                                                         bindTarget: bindPath.jointTransforms,
                                                         delay: delay)
                animations.append(skeletalAnimation)
            }
        }

        let groupAnimation = AnimationGroup(group: animations, name: name)
        return try AnimationResource.generate(with: groupAnimation)
    }

    func nodeIndex(of gltfNode: GLTFNode) -> Int {
        guard let nodes = sourceAsset?.nodes else { return 0 }
        return nodes.firstIndex(where: { $0 === gltfNode }) ?? 0
    }

    static func makeDocument(from asset: GLTFAsset) -> GLTFSessionDocument {
        var document = GLTFSessionDocument()
        document.defaultSceneIndex = asset.scenes.firstIndex(where: { $0 === asset.defaultScene }) ?? 0
        document.scenes = asset.scenes.map { scene in
            GLTFSessionDocument.Scene(
                name: scene.name ?? "",
                rootNodeIndices: scene.nodes.compactMap { node in
                    asset.nodes.firstIndex(where: { $0 === node })
                }
            )
        }
        document.nodes = asset.nodes.enumerated().map { index, node in
            makeNode(node, index: index, asset: asset)
        }
        document.meshes = asset.meshes.enumerated().map { _, mesh in
            makeMesh(mesh, asset: asset)
        }
        document.materials = asset.materials.map(makeMaterial)
        document.lights = asset.lights.map(makeLight)
        document.cameras = asset.cameras.map(makeCamera)
        document.animations = asset.animations.map(makeAnimation).filter { $0.duration > 0 }
        return document
    }

    static func makeNode(_ node: GLTFNode, index: Int, asset: GLTFAsset) -> GLTFSessionDocument.Node {
        GLTFSessionDocument.Node(
            index: index,
            name: node.name ?? "",
            children: node.childNodes.compactMap { child in
                asset.nodes.firstIndex(where: { $0 === child })
            },
            meshIndex: node.mesh.flatMap { mesh in
                asset.meshes.firstIndex(where: { $0 === mesh })
            },
            cameraIndex: node.camera.flatMap { camera in
                asset.cameras.firstIndex(where: { $0 === camera })
            },
            lightIndex: node.light.flatMap { light in
                asset.lights.firstIndex(where: { $0 === light })
            },
            translation: node.translation,
            rotation: node.rotation.vector,
            scale: node.scale
        )
    }

    static func makeMesh(_ mesh: GLTFMesh, asset: GLTFAsset) -> GLTFSessionDocument.Mesh {
        var triangleCount = 0
        var vertexCount = 0
        var materialIndices: [Int] = []
        for primitive in mesh.primitives {
            let verts = primitive.attribute(forName: "POSITION")?.accessor.count ?? 0
            vertexCount += verts
            if let indexCount = primitive.indices?.count {
                triangleCount += primitive.primitiveType == .triangles ? indexCount / 3 : 0
            } else if primitive.primitiveType == .triangles {
                triangleCount += verts / 3
            }
            if let material = primitive.material,
               let materialIndex = asset.materials.firstIndex(where: { $0 === material }) {
                materialIndices.append(materialIndex)
            }
        }
        return GLTFSessionDocument.Mesh(
            name: mesh.name ?? "",
            primitiveCount: mesh.primitives.count,
            triangleCount: triangleCount,
            vertexCount: vertexCount,
            materialIndices: materialIndices
        )
    }

    static func makeMaterial(_ material: GLTFMaterial) -> GLTFSessionDocument.Material {
        let metallicRoughness = material.metallicRoughness
        let alphaMode: String
        switch material.alphaMode {
        case .mask:
            alphaMode = "MASK"
        case .blend:
            alphaMode = "BLEND"
        default:
            alphaMode = "OPAQUE"
        }
        return GLTFSessionDocument.Material(
            name: material.name ?? "",
            baseColorFactor: metallicRoughness?.baseColorFactor ?? SIMD4(1, 1, 1, 1),
            metallicFactor: metallicRoughness?.metallicFactor ?? 1,
            roughnessFactor: metallicRoughness?.roughnessFactor ?? 1,
            emissiveFactor: material.emissive?.emissiveFactor ?? .zero,
            alphaMode: alphaMode,
            hasBaseColorTexture: metallicRoughness?.baseColorTexture != nil,
            hasMetallicRoughnessTexture: metallicRoughness?.metallicRoughnessTexture != nil,
            hasNormalTexture: material.normalTexture != nil,
            hasOcclusionTexture: material.occlusionTexture != nil,
            hasEmissiveTexture: material.emissive?.emissiveTexture != nil
        )
    }

    static func makeLight(_ light: GLTFLight) -> GLTFSessionDocument.Light {
        let type: String
        switch light.type {
        case .directional:
            type = "directional"
        case .point:
            type = "point"
        case .spot:
            type = "spot"
        default:
            type = "unknown"
        }
        return GLTFSessionDocument.Light(
            name: light.name ?? "",
            type: type,
            color: light.color,
            intensity: light.intensity,
            range: light.range > 0 ? light.range : nil,
            innerCone: light.type == .spot ? light.innerConeAngle : nil,
            outerCone: light.type == .spot ? light.outerConeAngle : nil
        )
    }

    static func makeCamera(_ camera: GLTFCamera) -> GLTFSessionDocument.Camera {
        let zfar = camera.zFar.isFinite ? camera.zFar : nil
        if let perspective = camera.perspective {
            return GLTFSessionDocument.Camera(
                name: camera.name ?? "",
                type: "perspective",
                yfov: perspective.yFOV,
                znear: camera.zNear,
                zfar: zfar,
                xmag: nil,
                ymag: nil
            )
        }
        return GLTFSessionDocument.Camera(
            name: camera.name ?? "",
            type: "orthographic",
            yfov: nil,
            znear: camera.zNear,
            zfar: zfar,
            xmag: camera.orthographic?.xMag,
            ymag: camera.orthographic?.yMag
        )
    }

    static func makeAnimation(_ animation: GLTFAnimation) -> GLTFSessionDocument.Animation {
        var maxTime: Float = 0
        for sampler in animation.samplers {
            if let hi = sampler.input.maxValues.first?.floatValue {
                maxTime = max(maxTime, hi)
            }
        }
        return GLTFSessionDocument.Animation(
            name: animation.name ?? "",
            duration: Double(maxTime)
        )
    }

    func platformColor(for vector: simd_float4) -> PlatformColor {
#if os(macOS)
        let components = [CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z), CGFloat(vector.w)]
        let color = NSColor(colorSpace: colorSpace, components: components, count: components.count)
        return color
#else
        let components = [CGFloat(vector.x), CGFloat(vector.y), CGFloat(vector.z), CGFloat(vector.w)]
        // TODO: Use proper color space (linear sRGB)
        let color = UIColor(red: components[0], green: components[1], blue: components[2], alpha: components[3])
        return color
#endif
    }
}

#endif // compiler >=5.6

#endif // !tvOS
