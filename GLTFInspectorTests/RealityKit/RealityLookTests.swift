@testable import RendererRealityKit
import Testing

struct RealityLookTests {
    @Test func iblExponentAddsExposureIntensityAndPolicyDim() {
        let dim = RealityPolicy.studioDimEV(fileHasLights: true)
        #expect(RealityLook.iblExponent(exposureEV: 0) == 0)
        #expect(RealityLook.iblExponent(exposureEV: 1) == 1)
        #expect(RealityLook.iblExponent(exposureEV: 0, dimEV: dim) == -2)
        #expect(RealityLook.iblExponent(exposureEV: 0.5, dimEV: dim) == -1.5)
        #expect(RealityLook.iblExponent(exposureEV: 0, environmentIntensity: 4) == 2)
    }

    /// Look-probe constants (seam 5): yaw 0 is the Khronos default view, lights × 591, spot × π
    /// with the full cone.
    @Test func renderLookMapsToRealityKitUnits() {
        #expect(abs(RealityLook.iblYaw(lookYawRadians: 0) - .pi) < 1e-6)
        #expect(abs(RealityLook.iblYaw(lookYawRadians: .pi / 2) - .pi / 2) < 1e-6)
        #expect(RealityLook.iblExponent(exposureEV: 1, dimEV: RealityPolicy.studioDimEV(fileHasLights: true)) == -1)
        #expect(RealityLook.directionalIntensity(lux: 1) == 591)
        #expect(abs(RealityLook.pointIntensity(candela: 1) - 4 * .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotIntensity(candela: 1) - .pi * 591) < 0.01)
        #expect(abs(RealityLook.spotConeDegrees(halfAngleRadians: .pi / 4) - 90) < 1e-4)
    }
}
