import SwiftUI

/// Write-through bridge from `EngineViewportController` (pills) into host canvas session
/// (`PreviewSessionBindings` / RealityKit). View-menu FocusedValues share the same bindings.
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
    var debugModeIndex: Binding<Int>
    /// Loaded-model debug cycle for `ViewMode` ↔ index mapping.
    var debugModes: [PreviewDebugMode]
}
