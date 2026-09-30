import GLTFCore
import PreviewUI
import RendererRealityKit
import SwiftUI

extension PreviewSession {
    /// Bindings for `RealityPreviewCanvas`. `debugModes` is the loaded model's RealityKit list;
    /// the canvas indexes it, the session keeps the neutral `viewMode`.
    func bindings(debugModes: [PreviewDebugMode]) -> PreviewSessionBindings {
        let modes = debugModes.isEmpty ? [PreviewDebugMode.none] : debugModes
        return PreviewSessionBindings(
            autoRotate: Binding(get: { self.autoRotate }, set: { self.autoRotate = $0 }),
            showFloor: Binding(get: { self.showFloor }, set: { self.showFloor = $0 }),
            backdropIndex: Binding(
                get: { PreviewBackground.index(matchingRawValue: self.backdrop.rawValue) },
                set: { self.backdrop = BackdropStyle(rawValue: PreviewBackground.at($0).rawValue) ?? .window }
            ),
            centerModel: Binding(get: { self.centerModel }, set: { self.centerModel = $0 }),
            orthographic: Binding(get: { self.orthographic }, set: { self.orthographic = $0 }),
            exposureEV: Binding(get: { self.exposureEV }, set: { self.exposureEV = $0 }),
            dimStudioForFileLights: Binding(
                get: { self.dimStudioForFileLights },
                set: { self.dimStudioForFileLights = $0 }
            ),
            environmentYaw: Binding(get: { self.environmentYaw }, set: { self.environmentYaw = $0 }),
            doubleSided: Binding(get: { self.doubleSided }, set: { self.doubleSided = $0 }),
            showSkeleton: Binding(get: { self.showSkeleton }, set: { self.showSkeleton = $0 }),
            fieldOfViewDegrees: Binding(
                get: { self.fieldOfViewDegrees },
                set: { self.fieldOfViewDegrees = $0 }
            ),
            debugModeIndex: Binding(
                get: { Self.debugModeIndex(for: self.viewMode, in: modes) },
                set: { index in
                    guard modes.indices.contains(index) else { return }
                    self.viewMode = modes[index].renderViewMode
                }
            ),
            debugModes: modes
        )
    }

    /// First RealityKit mode that shows `viewMode`; shaded (`.none`) when the model has none.
    static func debugModeIndex(for viewMode: RenderViewMode, in modes: [PreviewDebugMode]) -> Int {
        modes.firstIndex { $0.renderViewMode == viewMode }
            ?? modes.firstIndex(of: .none)
            ?? 0
    }
}
