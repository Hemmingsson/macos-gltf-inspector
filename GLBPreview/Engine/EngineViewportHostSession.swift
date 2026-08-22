import SwiftUI

/// Write-through bridge from `EngineViewportController` into host canvas session
/// (`PreviewSessionBindings` / RealityKit). Pills and the View menu share this bag.
@MainActor
struct EngineViewportHostSession {
    var backdropIndex: Binding<Int>
    var showFloor: Binding<Bool>
    var autoRotate: Binding<Bool>
    var centerModel: Binding<Bool>
    var orthographic: Binding<Bool>
    var exposureEV: Binding<Float>
    var dimStudioForFileLights: Binding<Bool>
    var environmentYaw: Binding<Float>
    var doubleSided: Binding<Bool>
    var showSkeleton: Binding<Bool>
    var fieldOfViewDegrees: Binding<Float>
    var debugModeIndex: Binding<Int>
    /// Loaded-model debug cycle for `ViewMode` ↔ index mapping.
    var debugModes: [PreviewDebugMode]
}
