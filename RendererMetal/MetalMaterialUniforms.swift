import Metal
import simd

struct GPUUVTransform {
    var row0 = SIMD4<Float>(1, 0, 0, 0)
    var row1 = SIMD4<Float>(0, 1, 0, 0)
    var row2 = SIMD4<Float>(0, 0, 1, 0)
    init(_ m: simd_float3x3 = matrix_identity_float3x3) {
        row0 = SIMD4(m[0][0], m[1][0], m[2][0], 0)
        row1 = SIMD4(m[0][1], m[1][1], m[2][1], 0)
        row2 = SIMD4(m[0][2], m[1][2], m[2][2], 0)
    }
}
struct GPUMaterial {
    var baseColor: SIMD4<Float>
    var emissiveNormalScale: SIMD4<Float>
    var surface: SIMD4<Float>
    var specular: SIMD4<Float>
    var coatTransmission: SIMD4<Float>
    var sheen: SIMD4<Float>
    var attenuation: SIMD4<Float>
    var volumeIridescence: SIMD4<Float>
    var anisotropy: SIMD4<Float>
    var flags: SIMD4<UInt32>
    var diffuseTransmissionColor: SIMD4<Float>
    var extra: SIMD4<Float>
    var uv0: GPUUVTransform
    var uv1: GPUUVTransform
    var uv2: GPUUVTransform
    var uv3: GPUUVTransform
    var uv4: GPUUVTransform
    var uv5: GPUUVTransform
    var uv6: GPUUVTransform
    var uv7: GPUUVTransform
    var uv8: GPUUVTransform
    var uv9: GPUUVTransform
    var uv10: GPUUVTransform
    var uv11: GPUUVTransform
    var uv12: GPUUVTransform
    var uv13: GPUUVTransform
    var uv14: GPUUVTransform
    var uv15: GPUUVTransform
    var uv16: GPUUVTransform
    var uv17: GPUUVTransform
    var uv18: GPUUVTransform
    var uv19: GPUUVTransform
    var uvSets0: SIMD4<UInt32>
    var uvSets1: SIMD4<UInt32>
    var uvSets2: SIMD4<UInt32>
    var uvSets3: SIMD4<UInt32>
    var uvSets4: SIMD4<UInt32>

    init(_ m: MetalMaterial) {
        baseColor = m.baseColor
        emissiveNormalScale = SIMD4(m.emissive, m.textures[.normal]?.scale ?? 1)
        surface = SIMD4(m.metallic, m.roughness, m.textures[.occlusion]?.scale ?? 1, m.alphaCutoff)
        specular = SIMD4(m.specularColor, m.specular)
        coatTransmission = SIMD4(m.clearcoat, m.clearcoatRoughness, m.ior, m.transmission)
        sheen = SIMD4(m.sheenColor, m.sheenRoughness)
        attenuation = SIMD4(m.attenuationColor, m.attenuationDistance.isFinite ? m.attenuationDistance : 0)
        volumeIridescence = SIMD4(m.thickness, m.iridescence, m.iridescenceIOR, m.iridescenceThicknessMax)
        anisotropy = SIMD4(m.anisotropy, m.anisotropyRotation, m.diffuseTransmission, 0)
        diffuseTransmissionColor = SIMD4(m.diffuseTransmissionColor, 0)
        extra = SIMD4(m.iridescenceThicknessMin, m.dispersion, m.glossiness, m.textures[.clearcoatNormal]?.scale ?? 1)
        let slots = MetalTextureSlot.allCases
        let mask = slots.enumerated().reduce(UInt32(0)) { $0 | (m.textures[$1.element] == nil ? 0 : UInt32(1 << $1.offset)) }
        flags = SIMD4(mask, UInt32(m.alphaMode), (m.unlit ? 1 : 0) | (m.doubleSided ? 2 : 0) | (m.isSpecularGlossiness ? 4 : 0),
                      (m.hasTexCoord0 ? 1 : 0) | (m.hasClearcoat ? 2 : 0) | (m.hasSpecular ? 4 : 0))
        uv0 = GPUUVTransform(m.textures[slots[0]]?.transform ?? matrix_identity_float3x3)
        uv1 = GPUUVTransform(m.textures[slots[1]]?.transform ?? matrix_identity_float3x3)
        uv2 = GPUUVTransform(m.textures[slots[2]]?.transform ?? matrix_identity_float3x3)
        uv3 = GPUUVTransform(m.textures[slots[3]]?.transform ?? matrix_identity_float3x3)
        uv4 = GPUUVTransform(m.textures[slots[4]]?.transform ?? matrix_identity_float3x3)
        uv5 = GPUUVTransform(m.textures[slots[5]]?.transform ?? matrix_identity_float3x3)
        uv6 = GPUUVTransform(m.textures[slots[6]]?.transform ?? matrix_identity_float3x3)
        uv7 = GPUUVTransform(m.textures[slots[7]]?.transform ?? matrix_identity_float3x3)
        uv8 = GPUUVTransform(m.textures[slots[8]]?.transform ?? matrix_identity_float3x3)
        uv9 = GPUUVTransform(m.textures[slots[9]]?.transform ?? matrix_identity_float3x3)
        uv10 = GPUUVTransform(m.textures[slots[10]]?.transform ?? matrix_identity_float3x3)
        uv11 = GPUUVTransform(m.textures[slots[11]]?.transform ?? matrix_identity_float3x3)
        uv12 = GPUUVTransform(m.textures[slots[12]]?.transform ?? matrix_identity_float3x3)
        uv13 = GPUUVTransform(m.textures[slots[13]]?.transform ?? matrix_identity_float3x3)
        uv14 = GPUUVTransform(m.textures[slots[14]]?.transform ?? matrix_identity_float3x3)
        uv15 = GPUUVTransform(m.textures[slots[15]]?.transform ?? matrix_identity_float3x3)
        uv16 = GPUUVTransform(m.textures[slots[16]]?.transform ?? matrix_identity_float3x3)
        uv17 = GPUUVTransform(m.textures[slots[17]]?.transform ?? matrix_identity_float3x3)
        uv18 = GPUUVTransform(m.textures[slots[18]]?.transform ?? matrix_identity_float3x3)
        uv19 = GPUUVTransform(m.textures[slots[19]]?.transform ?? matrix_identity_float3x3)
        uvSets0 = SIMD4(UInt32(m.textures[slots[0]]?.texCoord ?? 0),UInt32(m.textures[slots[1]]?.texCoord ?? 0),UInt32(m.textures[slots[2]]?.texCoord ?? 0),UInt32(m.textures[slots[3]]?.texCoord ?? 0))
        uvSets1 = SIMD4(UInt32(m.textures[slots[4]]?.texCoord ?? 0),UInt32(m.textures[slots[5]]?.texCoord ?? 0),UInt32(m.textures[slots[6]]?.texCoord ?? 0),UInt32(m.textures[slots[7]]?.texCoord ?? 0))
        uvSets2 = SIMD4(UInt32(m.textures[slots[8]]?.texCoord ?? 0),UInt32(m.textures[slots[9]]?.texCoord ?? 0),UInt32(m.textures[slots[10]]?.texCoord ?? 0),UInt32(m.textures[slots[11]]?.texCoord ?? 0))
        uvSets3 = SIMD4(UInt32(m.textures[slots[12]]?.texCoord ?? 0),UInt32(m.textures[slots[13]]?.texCoord ?? 0),UInt32(m.textures[slots[14]]?.texCoord ?? 0),UInt32(m.textures[slots[15]]?.texCoord ?? 0))
        uvSets4 = SIMD4(UInt32(m.textures[slots[16]]?.texCoord ?? 0),UInt32(m.textures[slots[17]]?.texCoord ?? 0),UInt32(m.textures[slots[18]]?.texCoord ?? 0),UInt32(m.textures[slots[19]]?.texCoord ?? 0))

    }
}

/// Material resources use a tier-2 argument buffer, preserving one glTF sampler per map
/// without exhausting Metal's 16 directly bound sampler slots.
final class MetalMaterialResources {
    private let arguments: any MTLBuffer
    private let textures: [any MTLTexture]
    init(_ material: MetalMaterial, device: any MTLDevice, library: any MTLLibrary) throws {
        guard let function = library.makeFunction(name: "khronos_fragment") else {
            throw MetalRendererError.resource("material fragment function")
        }
        let encoder = function.makeArgumentEncoder(bufferIndex: 5)
        guard let buffer = device.makeBuffer(length: encoder.encodedLength, options: .storageModeShared) else {
            throw MetalRendererError.resource("material argument buffer")
        }
        encoder.setArgumentBuffer(buffer, offset: 0)
        var resources: [any MTLTexture] = []
        for (index, slot) in MetalTextureSlot.allCases.enumerated() {
            let binding = material.textures[slot]
            encoder.setTexture(binding?.texture, index: index)
            encoder.setSamplerState(binding?.sampler, index: index + 20)
            if let binding { resources.append(binding.texture) }
        }
        arguments = buffer
        textures = resources
    }
    func bind(_ encoder: any MTLRenderCommandEncoder) {
        for texture in textures { encoder.useResource(texture, usage: .read, stages: .fragment) }
        encoder.setFragmentBuffer(arguments, offset: 0, index: 5)
    }
}

struct GPULight {
    var directionRange: SIMD4<Float>
    var colorIntensity: SIMD4<Float>
    var positionInnerCone: SIMD4<Float>
    var outerType: SIMD4<Float>
    static var zero: GPULight { GPULight() }
    private init() { directionRange = .zero; colorIntensity = .zero; positionInnerCone = .zero; outerType = .zero }
    init(_ light: MetalPunctualLight) {
        directionRange = SIMD4(light.direction, light.range)
        colorIntensity = SIMD4(light.color, light.intensity)
        positionInnerCone = SIMD4(light.position, light.innerConeCos)
        outerType = SIMD4(light.outerConeCos, Float(light.type), 0, 0)
    }
}
