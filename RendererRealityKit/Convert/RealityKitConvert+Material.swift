import RealityKit
import GLTFKit2
import simd

private enum MaterialBlendDecision {
    case none
    case mask(Float)
    case factorTransparent(Float)
    case cutout
    case opaque
}

private let detectedCutoutOpacityThreshold: Float = 0.4

extension RealityKitConvert {
    @MainActor func convert(material gltfMaterial: GLTFMaterial?,
                            context: RealityKitResourceContext) throws -> any RealityKit.Material
    {
        guard let gltfMaterial = gltfMaterial else {
            return context.defaultMaterial
        }
        if let cached = context.cachedConvertedMaterial(for: gltfMaterial) {
            return cached
        }

        let name = gltfMaterial.name
        let converted: any RealityKit.Material
        if gltfMaterial.isUnlit {
            var material = UnlitMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.color.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.color.texture = context.requiredTexture(
                        for: baseColorTexture,
                        channels: .all,
                        semantic: .color,
                        materialName: name
                    )
                }
            }
            applyBlendMode(toUnlit: &material, gltfMaterial: gltfMaterial, context: context)
            converted = material
        } else {
            var material = PhysicallyBasedMaterial()
            if let metallicRoughness = gltfMaterial.metallicRoughness {
                material.baseColor.tint = platformColor(for: metallicRoughness.baseColorFactor)
                if let baseColorTexture = metallicRoughness.baseColorTexture {
                    material.baseColor.texture = context.requiredTexture(
                        for: baseColorTexture,
                        channels: .all,
                        semantic: .color,
                        materialName: name
                    )
                }
                material.roughness.scale = metallicRoughness.roughnessFactor
                material.metallic.scale = metallicRoughness.metallicFactor
                if let metallicRoughnessTexture = metallicRoughness.metallicRoughnessTexture {
                    material.roughness.texture = context.requiredTexture(
                        for: metallicRoughnessTexture,
                        channels: .green,
                        semantic: .scalar,
                        materialName: name
                    )
                    material.metallic.texture = context.requiredTexture(
                        for: metallicRoughnessTexture,
                        channels: .blue,
                        semantic: .scalar,
                        materialName: name
                    )
                }
            }
            if let specular = gltfMaterial.specular {
                var spec = PhysicallyBasedMaterial.Specular(scale: specular.specularFactor)
                if let specularTexture = specular.specularTexture {
                    spec.texture = context.requiredTexture(
                        for: specularTexture,
                        channels: .alpha,
                        semantic: .scalar,
                        materialName: name
                    )
                }
                material.specular = spec
            } else {
                material.specular = .init(floatLiteral: 0)
            }
            if let normal = gltfMaterial.normalTexture, abs(normal.scale) > 0.0001 {
                material.normal.texture = context.requiredTexture(
                    for: normal,
                    channels: .all,
                    semantic: .normal,
                    materialName: name
                )
            }
            if let emissive = gltfMaterial.emissive {
                let hint = PreviewEmissive.hint(from: gltfMaterial)
                if !PreviewEmissive.shouldIgnore(hint, fileLooksBaked: ignoreBakedEmissive) {
                    var emissiveTexture: PhysicallyBasedMaterial.Texture?
                    if let texture = emissive.emissiveTexture {
                        emissiveTexture = context.requiredTexture(
                            for: texture,
                            channels: .all,
                            semantic: .color,
                            materialName: name
                        )
                    }
                    material.emissiveColor = .init(
                        color: platformColor(for: simd_make_float4(emissive.emissiveFactor, 1)),
                        texture: emissiveTexture
                    )
                    material.emissiveIntensity = emissive.emissiveStrength
                }
            }
            if let occlusion = gltfMaterial.occlusionTexture {
                material.ambientOcclusion.texture = context.requiredTexture(
                    for: occlusion,
                    channels: .red,
                    semantic: .scalar,
                    materialName: name
                )
            }
            if let clearcoat = gltfMaterial.clearcoat {
                material.clearcoat.scale = clearcoat.clearcoatFactor
                if let clearcoatTexture = clearcoat.clearcoatTexture {
                    material.clearcoat.texture = context.requiredTexture(
                        for: clearcoatTexture,
                        channels: .red,
                        semantic: .raw,
                        materialName: name
                    )
                }
                material.clearcoatRoughness.scale = clearcoat.clearcoatRoughnessFactor
                if let clearcoatRoughnessTexture = clearcoat.clearcoatRoughnessTexture {
                    material.clearcoatRoughness.texture = context.requiredTexture(
                        for: clearcoatRoughnessTexture,
                        channels: .green,
                        semantic: .raw,
                        materialName: name
                    )
                }
                if let clearcoatNormalTexture = clearcoat.clearcoatNormalTexture {
                    material.clearcoatNormal = .init(
                        texture: context.requiredTexture(
                            for: clearcoatNormalTexture,
                            channels: .all,
                            semantic: .normal,
                            materialName: name
                        )
                    )
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
                    sheenColor.texture = context.requiredTexture(
                        for: sheenTexture,
                        channels: .all,
                        semantic: .color,
                        materialName: name
                    )
                }
                material.sheen = sheenColor
            }
            if let transmission = gltfMaterial.transmission, transmission.transmissionFactor > 0 {
                let opacity = min(1, max(0.08, 1 - transmission.transmissionFactor))
                material.blending = .transparent(opacity: .init(scale: opacity))
                context.record(
                    .approximatedTransmission,
                    severity: .warning,
                    message: "Transmission approximated as opacity",
                    materialName: name
                )
            }
            converted = material
        }
        context.storeConvertedMaterial(converted, for: gltfMaterial)
        return converted
    }

    @MainActor
    func applyBlendMode(
        toPBR material: inout PhysicallyBasedMaterial,
        gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext
    ) {
        switch blendDecision(for: gltfMaterial, context: context) {
        case .none:
            return
        case .mask(let cutoff):
            material.opacityThreshold = cutoff
        case .factorTransparent(let alpha):
            var opacity = PhysicallyBasedMaterial.Opacity(scale: alpha)
            if let texture = gltfMaterial.metallicRoughness?.baseColorTexture {
                opacity.texture = context.texture(for: texture, channels: .alpha, semantic: .scalar)
            }
            material.blending = .transparent(opacity: opacity)
        case .cutout:
            material.opacityThreshold = detectedCutoutOpacityThreshold
        case .opaque:
            material.blending = .opaque
            if gltfMaterial.alphaMode == .blend {
                context.record(
                    .forcedOpaqueBlend,
                    severity: .warning,
                    message: "BLEND forced opaque",
                    materialName: gltfMaterial.name
                )
            }
        }
    }

    @MainActor
    func applyBlendMode(
        toUnlit material: inout UnlitMaterial,
        gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext
    ) {
        switch blendDecision(for: gltfMaterial, context: context) {
        case .none:
            return
        case .mask(let cutoff):
            material.opacityThreshold = cutoff
        case .factorTransparent:
            material.blending = .transparent(opacity: 1.0)
        case .cutout:
            material.opacityThreshold = detectedCutoutOpacityThreshold
        case .opaque:
            material.blending = .opaque
            if gltfMaterial.alphaMode == .blend {
                context.record(
                    .forcedOpaqueBlend,
                    severity: .warning,
                    message: "BLEND forced opaque",
                    materialName: gltfMaterial.name
                )
            }
        }
    }

    /// Factor 1 + BLEND + empty/zero texture alpha is Sketchfab car paint (invisible
    /// if blended). Factor 1 + BLEND + a real alpha span is foliage / decals.
    /// Detected cutout: treat like native MASK (threshold only, no opacity texture).
    @MainActor
    private func blendDecision(
        for gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext
    ) -> MaterialBlendDecision {
        if gltfMaterial.alphaMode == .mask {
            return .mask(gltfMaterial.alphaCutoff)
        }
        guard gltfMaterial.alphaMode == .blend else { return .none }
        let alpha = gltfMaterial.metallicRoughness?.baseColorFactor.w ?? 1
        if alpha < 0.999 {
            return .factorTransparent(alpha)
        }
        if let texture = gltfMaterial.metallicRoughness?.baseColorTexture,
           context.alphaUsage(for: texture) == .cutout
        {
            return .cutout
        }
        return .opaque
    }
}
