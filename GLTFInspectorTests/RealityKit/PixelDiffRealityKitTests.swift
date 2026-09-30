import CoreGraphics
import Foundation
@testable import GLTFCore
@testable import RendererRealityKit
import simd
import Testing

/// The RealityKit renderer in the pixel-diff harness: the shipping `EntityLoader.loadThumbnail`
/// → `StillRenderer` path, posed from the same manifest camera as the web goldens. The
/// comparator, manifest and loops are renderer-neutral (`PixelDiff*.swift` at the test root).
///
/// Look mapping (RealityKit is never compared against the web; this only says what is pinned):
///
/// | Manifest | RealityKit | Status |
/// | --- | --- | --- |
/// | `environment` | `AppLook` catalog of that name, IBL on | pinned, not read from the user's `look.json` |
/// | `environmentRotationDegrees` | `RenderLook` yaw = rotation − 90 → IBL yaw π − Y (`RealityLook`) | measured (seam 5) |
/// | `exposureEV` | `RealityLook.iblExponent` — IBL only, plus the `RealityPolicy` file-light dim | IBL-only exposure (research G2) |
/// | `toneMapping` | system tone map | PBR Neutral not available (decision 2 → B) |
/// | `background` | opaque ``PixelDiff/backdrop`` grey | `StillRenderer` output carries no alpha |
@MainActor
enum PixelDiffRealityKit {
    /// Manifest rotation is the page's; the page's 90 is `RenderLook` yaw 0 (Khronos default).
    static func lookYawRadians(_ look: PixelDiffManifest.Look) -> Float {
        Float((look.environmentRotationDegrees - 90) * .pi / 180)
    }

    static func make(manifest: PixelDiffManifest) -> PixelDiffRun.Render {
        { entry in try await render(entry, look: manifest.look) }
    }

    static func render(
        _ entry: PixelDiffManifest.Entry,
        look: PixelDiffManifest.Look
    ) async throws -> CGImage {
        let camera = try PixelDiffRun.camera(of: entry)
        let model = try await EntityLoader.loadThumbnail(from: entry.modelURL)
        let still = try await StillRenderer(
            root: model.entity,
            cameraPose: stillPose(camera),
            width: look.canvasSize,
            height: look.canvasSize,
            background: CGColor(
                srgbRed: CGFloat(PixelDiff.backdrop.r) / 255,
                green: CGFloat(PixelDiff.backdrop.g) / 255,
                blue: CGFloat(PixelDiff.backdrop.b) / 255,
                alpha: 1
            ),
            intensityExponent: RealityLook.iblExponent(
                exposureEV: Float(look.exposureEV),
                dimEV: model.studioIBLExponent
            ),
            environmentYaw: lookYawRadians(look),
            look: AppLook(useEnvironmentMap: true, catalogRaw: look.environment, customFileName: nil)
        )
        return try await still.capture()
    }

    /// The page's orbit camera, in RealityKit terms. Khronos `UserCamera.setRotation` builds
    /// `Ry(azimuth) * Rx(elevation)` and places the eye `distance` along that rotation's +Z from
    /// the target; both engines look down −Z with +Y up, and the converter keeps glTF axes.
    nonisolated static func stillPose(_ pose: PixelDiffManifest.Camera) -> StillCameraPose {
        let yaw = simd_quatf(angle: Float(pose.azimuth * .pi / 180), axis: [0, 1, 0])
        let pitch = simd_quatf(angle: Float(pose.elevation * .pi / 180), axis: [1, 0, 0])
        let orientation = yaw * pitch
        let target = SIMD3<Float>(pose.target.map(Float.init))
        return StillCameraPose(
            position: target + orientation.act([0, 0, Float(pose.distance)]),
            orientation: orientation,
            projection: .perspective(
                fieldOfViewDegrees: Float(pose.yfov * 180 / .pi),
                near: Float(pose.znear),
                far: Float(pose.zfar)
            )
        )
    }
}

/// The safety net for RealityKit: every pinned sample rendered and compared against
/// `TestModels/References/realitykit/`.
@MainActor
@Suite(.serialized)
struct PixelDiffRealityKitTests {
    @Test func everySampleMatchesItsReference() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.expectEverySampleMatches(
            .realitykit, manifest: manifest, render: PixelDiffRealityKit.make(manifest: manifest)
        )
    }

    @Test func everyReferenceImageIsPresentAndTheRightShape() throws {
        try PixelDiffRun.expectEveryReferenceIsPresent(.realitykit)
    }
}

/// Rewrites the RealityKit references from the poses the manifest already records (the web
/// generator records them; run it first when both are regenerated — the script does). Off
/// unless asked for:
///
///     ./scripts/regenerate-pixel-references.sh [realitykit]
@MainActor
struct PixelDiffRealityKitRegeneration {
    @Test(.enabled(if: PixelDiffRegeneration.isRequested(for: .realitykit)))
    func regenerate() async throws {
        let manifest = try PixelDiffManifest.load()
        try #require(!manifest.entries.isEmpty, "no pinned samples to render")
        try await PixelDiffRun.regenerate(
            .realitykit, manifest: manifest, render: PixelDiffRealityKit.make(manifest: manifest)
        )
    }

    /// `./scripts/regenerate-pixel-references.sh --measure-noise`
    @Test(.enabled(if: PixelDiffRegeneration.isNoiseMeasurementRequested))
    func measureNoise() async throws {
        let manifest = try PixelDiffManifest.load()
        try await PixelDiffRun.measureNoise(.realitykit, manifest: manifest) {
            PixelDiffRealityKit.make(manifest: manifest)
        }
    }
}
