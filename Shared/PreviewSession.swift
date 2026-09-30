import GLTFCore
import Observation
import RendererRealityKit
import SwiftUI

/// Host-owned preview session state — single source of truth for the RealityKit canvas.
///
/// Quick Look does not use this type; `PreviewScene` keeps local `@State` when `session` bindings are nil.
@MainActor
@Observable
final class PreviewSession {
    var autoRotate = true
    var showFloor = true
    var backdropIndex = PreviewBackground.storedIndex
    var centerModel = true
    var orthographic = false
    var exposureEV: Float = 0
    var dimStudioForFileLights = false
    var environmentYaw: Float = 0
    var doubleSided = false
    var showSkeleton = false
    var fieldOfViewDegrees = RenderCamera.defaultFieldOfViewDegrees
    var debugModeIndex = 0
    var debugModes: [PreviewDebugMode] = [.none]

    /// Bindings for `PreviewScene` / `PreviewView` (host path only).
    var bindings: PreviewSessionBindings {
        PreviewSessionBindings(
            autoRotate: Binding(get: { self.autoRotate }, set: { self.autoRotate = $0 }),
            showFloor: Binding(get: { self.showFloor }, set: { self.showFloor = $0 }),
            backdropIndex: Binding(get: { self.backdropIndex }, set: { self.backdropIndex = $0 }),
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
            debugModeIndex: Binding(get: { self.debugModeIndex }, set: { self.debugModeIndex = $0 }),
            debugModes: debugModes
        )
    }
}
