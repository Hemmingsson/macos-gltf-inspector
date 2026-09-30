import Foundation
import GLTFCore

/// `RenderLook` → RealityKit, in one place. Constants come from the look probes
/// (`.agents/research/2026-09-30-look-probes.md`); each row says whether it is measured.
///
/// | Look / glTF value | RealityKit | Status |
/// | --- | --- | --- |
/// | `environmentYawDegrees` Y (0 = Khronos default view) | IBL entity yaw = π − Y | measured (≤ 7° residual, RK IBL filtering) |
/// | `exposureEV` EV | IBL `intensityExponent` + EV | measured for IBL; punctual × 2^EV and emissive × 2^EV **not applied** (lights are built once at convert) |
/// | `environmentIntensity` E | IBL `intensityExponent` + log2 E | measured at E = 1 (gain 1.00 ± 7 %) |
/// | directional lux | lux × 591 | measured (RK exposes at a fixed ≈ EV 9) |
/// | point cd | lm = cd · 4π · 591 | measured |
/// | spot cd | lm = cd · π · 591 | measured (RK spot cd = lm/π, cone-independent) |
/// | spot inner/outer half-angle | degrees × 2 (RK angles are the full cone) | measured (outer); inner assumed |
/// | emissive | 1:1 (not scaled by 591) | measured |
/// | tone mapping | system tone map | decision 2 → B (no PBR Neutral on RK) |
///
/// The studio dim for files with their own lights is product policy, not mapping:
/// ``RealityPolicy/studioDimEV(fileHasLights:)``.
enum RealityLook {
    /// Web lux → RealityKit lux on a rough white dielectric (≈ 2^9.2).
    static let punctualScale: Float = 591

    /// RealityKit `ImageBasedLight` entity yaw for a look yaw in radians (0 = Khronos default).
    static func iblYaw(lookYawRadians: Float) -> Float {
        .pi - lookYawRadians
    }

    /// IBL `intensityExponent`: exposure plus environment intensity, plus any policy dim.
    static func iblExponent(exposureEV: Float, environmentIntensity: Float = 1, dimEV: Float = 0) -> Float {
        exposureEV + log2(max(environmentIntensity, .leastNormalMagnitude)) + dimEV
    }

    static func directionalIntensity(lux: Float) -> Float {
        lux * punctualScale
    }

    static func pointIntensity(candela: Float) -> Float {
        candela * 4 * .pi * punctualScale
    }

    static func spotIntensity(candela: Float) -> Float {
        candela * .pi * punctualScale
    }

    /// glTF cone angles are half-angles in radians; RealityKit takes the full cone in degrees.
    static func spotConeDegrees(halfAngleRadians: Float) -> Float {
        2 * halfAngleRadians * 180 / .pi
    }
}

extension RenderLook {
    /// IBL entity yaw for this look.
    var realityKitIBLYaw: Float {
        RealityLook.iblYaw(lookYawRadians: Float(environmentYawDegrees * .pi / 180))
    }

    /// IBL `intensityExponent` for this look, with the studio dim when the file brings lights.
    func realityKitIBLExponent(fileHasLights: Bool) -> Float {
        RealityLook.iblExponent(
            exposureEV: Float(exposureEV),
            environmentIntensity: Float(environmentIntensity),
            dimEV: RealityPolicy.studioDimEV(fileHasLights: fileHasLights)
        )
    }
}
