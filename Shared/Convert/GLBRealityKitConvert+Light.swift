import RealityKit
import GLTFKit2
import simd

extension GLBRealityKitConvert {
    func convert(spotLight gltfLight: GLTFLight) -> SpotLightComponent {
        let light = SpotLightComponent(color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                       intensity: gltfLight.intensity * 4 * .pi,
                                       innerAngleInDegrees: GLTFDegFromRad(gltfLight.innerConeAngle),
                                       outerAngleInDegrees: GLTFDegFromRad(gltfLight.outerConeAngle),
                                       attenuationRadius: punctualAttenuationRadius(gltfLight.range))
        return light
    }

    func convert(pointLight gltfLight: GLTFLight) -> PointLightComponent {
        let light = PointLightComponent(color:platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
                                        intensity: gltfLight.intensity * 4 * .pi,
                                        attenuationRadius: punctualAttenuationRadius(gltfLight.range))
        return light
    }

    func convert(directionalLight gltfLight: GLTFLight) -> DirectionalLightComponent {
        DirectionalLightComponent(
            color: platformColor(for: simd_make_float4(gltfLight.color, 1.0)),
            intensity: gltfLight.intensity,
            isRealWorldProxy: false
        )
    }

    /// glTF `range <= 0` means infinite; RealityKit rejects a zero radius.
    private func punctualAttenuationRadius(_ range: Float) -> Float {
        range > 0 ? range : 1_000_000
    }
}
