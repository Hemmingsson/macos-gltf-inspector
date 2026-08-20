import RealityKit
import GLTFKit2
import simd

extension RealityKitConvert {
    @MainActor func convert(material gltfMaterial: GLTFMaterial?,
                            context: RealityKitResourceContext) throws -> any RealityKit.Material
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
                let hint = PreviewEmissive.hint(from: gltfMaterial)
                if !PreviewEmissive.shouldIgnore(hint, fileLooksBaked: ignoreBakedEmissive) {
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
                if let clearcoatNormalTexture = clearcoat.clearcoatNormalTexture {
                    material.clearcoatNormal = .init(
                        texture: context.texture(for: clearcoatNormalTexture, channels: .all, semantic: .normal)
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
        context: RealityKitResourceContext
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
        context: RealityKitResourceContext
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
}
