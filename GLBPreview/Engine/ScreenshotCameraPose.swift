import AppKit
import RealityKit

/// Offscreen still capture at the live camera pose (not a RealityView framebuffer grab).
/// Extracted so `EngineViewportController.screenshot()` can share the path.
enum ScreenshotCameraPose {
    /// Clones `pivot`, samples `camera` into a `StillCameraPose`, and presents the save panel.
    @MainActor
    static func capture(
        camera: Entity,
        pivot: Entity,
        dimStudioForFileLights: Bool,
        exposureEV: Float,
        backdropIndex: Int,
        environmentYaw: Float,
        suggestedName: String
    ) {
        Task { @MainActor in
            guard let pose = StillCameraPose.capturing(from: camera) else {
                AppLog.error(AppLog.host, "screenshot skipped — no live camera pose")
                return
            }
            let root = pivot.clone(recursive: true)
            let intensity = PreviewEmissive.sessionIBLExponent(
                dimStudioForFileLights: dimStudioForFileLights,
                exposureEV: exposureEV
            )
            let background = PreviewBackground.at(backdropIndex).stillBackgroundCGColor
            let aspect: Float = {
                if let view = NSApp.keyWindow?.contentView, view.bounds.height > 1 {
                    return Float(view.bounds.width / view.bounds.height)
                }
                return 16 / 9
            }()
            do {
                let url = try await StillRenderer.exportPNGViaSavePanel(
                    root: root,
                    cameraPose: pose,
                    background: background,
                    intensityExponent: intensity,
                    environmentYaw: environmentYaw,
                    suggestedName: suggestedName,
                    aspect: aspect
                )
                if let url {
                    AppLog.info(
                        AppLog.host,
                        "screenshot wrote \(url.path) (offscreen re-render at live camera pose)"
                    )
                }
            } catch {
                AppLog.error(AppLog.host, "screenshot failed: \(error.localizedDescription)")
            }
        }
    }
}
