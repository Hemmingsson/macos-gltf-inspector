import RealityKit
import GLTFKit2
import simd

/// How one material blends, after the spec mapping and the reported policy override.
private enum MaterialBlendDecision {
    case none
    /// glTF MASK, or the policy's detected cutout.
    case mask(Float)
    /// glTF BLEND: opacity = baseColorFactor.a × baseColorTexture.a.
    case transparent(Float)
    case opaque
}

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
        func tex(
            _ params: GLTFTextureParams,
            _ channels: RealityKitResourceContext.ColorMask,
            _ semantic: RealityKit.TextureResource.Semantic
        ) -> RealityKit.PhysicallyBasedMaterial.Texture? {
            context.requiredTexture(for: params, channels: channels, semantic: semantic, materialName: name)
        }
        let converted: any RealityKit.Material = gltfMaterial.isUnlit
            ? makeUnlit(gltfMaterial, context: context, tex: tex)
            : makePBR(gltfMaterial, context: context, tex: tex)
        context.storeConvertedMaterial(converted, for: gltfMaterial)
        return converted
    }

    @MainActor
    private func makeUnlit(
        _ gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext,
        tex: (GLTFTextureParams, RealityKitResourceContext.ColorMask, RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    ) -> UnlitMaterial {
        var material = UnlitMaterial()
        if let metallicRoughness = gltfMaterial.metallicRoughness {
            material.color.tint = platformColor(for: metallicRoughness.baseColorFactor)
            if let baseColorTexture = metallicRoughness.baseColorTexture {
                material.color.texture = tex(baseColorTexture, .all, .color)
            }
        }
        applyBlendMode(toUnlit: &material, gltfMaterial: gltfMaterial, context: context)
        let transforms = TextureTransforms.transforms(for: gltfMaterial, context: context)
        if let primary = transforms[0] { material.textureCoordinateTransform = primary }
        if let secondary = transforms[1], secondary.offset != .zero || secondary.scale != [1, 1] || secondary.rotation != 0 {
            context.record(
                .approximatedTextureTransform,
                severity: .warning,
                message: "Unlit materials have no UV1 transform",
                materialName: gltfMaterial.name
            )
        }
        return material
    }

    @MainActor
    private func makePBR(
        _ gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext,
        tex: (GLTFTextureParams, RealityKitResourceContext.ColorMask, RealityKit.TextureResource.Semantic) -> RealityKit.PhysicallyBasedMaterial.Texture?
    ) -> PhysicallyBasedMaterial {
        let name = gltfMaterial.name
        var material = PhysicallyBasedMaterial()
        if let metallicRoughness = gltfMaterial.metallicRoughness {
            material.baseColor.tint = platformColor(for: metallicRoughness.baseColorFactor)
            if let baseColorTexture = metallicRoughness.baseColorTexture {
                material.baseColor.texture = tex(baseColorTexture, .all, .color)
            }
            material.roughness.scale = metallicRoughness.roughnessFactor
            material.metallic.scale = metallicRoughness.metallicFactor
            if let metallicRoughnessTexture = metallicRoughness.metallicRoughnessTexture {
                material.roughness.texture = tex(metallicRoughnessTexture, .green, .scalar)
                material.metallic.texture = tex(metallicRoughnessTexture, .blue, .scalar)
            }
        }
        if let specular = gltfMaterial.specular {
            var spec = PhysicallyBasedMaterial.Specular(scale: specular.specularFactor)
            if let specularTexture = specular.specularTexture {
                spec.texture = tex(specularTexture, .alpha, .scalar)
            }
            material.specular = spec
        } else {
            material.specular = .init(floatLiteral: 0)
        }
        if let normal = gltfMaterial.normalTexture, abs(normal.scale) > 0.0001 {
            material.normal.texture = tex(normal, .all, .normal)
        }
        if let emissive = gltfMaterial.emissive {
            let hint = RealityPolicy.EmissiveHint(gltfMaterial)
            if RealityPolicy.dropsEmissive(hint, fileLooksBaked: ignoreBakedEmissive) {
                if hint.hasEmissive {
                    context.record(.droppedEmissive, severity: .warning, message: "Baked / boost emissive dropped", materialName: name)
                }
            } else {
                material.emissiveColor = .init(
                    color: platformColor(for: simd_make_float4(emissive.emissiveFactor, 1)),
                    texture: emissive.emissiveTexture.map { tex($0, .all, .color) }
                )
                material.emissiveIntensity = emissive.emissiveStrength
            }
        }
        if let occlusion = gltfMaterial.occlusionTexture {
            material.ambientOcclusion.texture = tex(occlusion, .red, .scalar)
        }
        if let clearcoat = gltfMaterial.clearcoat {
            material.clearcoat.scale = clearcoat.clearcoatFactor
            if let clearcoatTexture = clearcoat.clearcoatTexture {
                material.clearcoat.texture = tex(clearcoatTexture, .red, .raw)
            }
            material.clearcoatRoughness.scale = clearcoat.clearcoatRoughnessFactor
            if let clearcoatRoughnessTexture = clearcoat.clearcoatRoughnessTexture {
                material.clearcoatRoughness.texture = tex(clearcoatRoughnessTexture, .green, .raw)
            }
            if let clearcoatNormalTexture = clearcoat.clearcoatNormalTexture {
                material.clearcoatNormal = .init(texture: tex(clearcoatNormalTexture, .all, .normal))
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
                sheenColor.texture = tex(sheenTexture, .all, .color)
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
        let transforms = TextureTransforms.transforms(for: gltfMaterial, context: context)
        if let primary = transforms[0] { material.textureCoordinateTransform = primary }
        if let secondary = transforms[1] { material.secondaryTextureCoordinateTransform = secondary }
        return material
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
        case .transparent(let alpha):
            var opacity = PhysicallyBasedMaterial.Opacity(scale: alpha)
            if let texture = gltfMaterial.metallicRoughness?.baseColorTexture {
                opacity.texture = context.texture(for: texture, channels: .alpha, semantic: .scalar)
            }
            material.blending = .transparent(opacity: opacity)
        case .opaque:
            material.blending = .opaque
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
        case .transparent:
            material.blending = .transparent(opacity: 1.0)
        case .opaque:
            material.blending = .opaque
        }
    }

    /// Spec mapping (MASK → threshold, BLEND → transparent with factor × texture alpha), then the
    /// reported `RealityPolicy.blendOverride` for factor-1 BLEND.
    @MainActor
    private func blendDecision(
        for gltfMaterial: GLTFMaterial,
        context: RealityKitResourceContext
    ) -> MaterialBlendDecision {
        switch gltfMaterial.alphaMode {
        case .mask:
            return .mask(gltfMaterial.alphaCutoff)
        case .blend:
            break
        default:
            return .none
        }
        let alpha = gltfMaterial.metallicRoughness?.baseColorFactor.w ?? 1
        let textureAlpha = gltfMaterial.metallicRoughness?.baseColorTexture.map(context.alphaUsage(for:))
        switch RealityPolicy.blendOverride(factorAlpha: alpha, textureAlpha: textureAlpha) {
        case nil:
            return .transparent(alpha)
        case .opaque:
            context.record(.forcedOpaqueBlend, severity: .warning, message: "BLEND forced opaque", materialName: gltfMaterial.name)
            return .opaque
        case .cutout(let threshold):
            context.record(.blendAsCutout, severity: .warning, message: "BLEND drawn as cutout", materialName: gltfMaterial.name)
            return .mask(threshold)
        }
    }
}
