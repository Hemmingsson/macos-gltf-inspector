import SwiftUI

/// Host-owned preview chrome bindings (P34). Quick Look leaves `session` nil and
/// uses local `@State` in `PreviewScene` instead.
struct PreviewSessionBindings {
    var autoRotate: Binding<Bool>
    var showFloor: Binding<Bool>
    var backdropIndex: Binding<Int>
    var centerModel: Binding<Bool>
    var orthographic: Binding<Bool>
    var exposureEV: Binding<Float>
    var dimStudioForFileLights: Binding<Bool>
    var environmentYaw: Binding<Float>
    var doubleSided: Binding<Bool>
    var showSkeleton: Binding<Bool>
    var fieldOfViewDegrees: Binding<Float>
    /// Look / view-mode cycle index into `PreviewScene.debugModes` (host pills + old chrome).
    var debugModeIndex: Binding<Int>
    /// Host ViewMode ↔ index map. Quick Look leaves `session` nil.
    var debugModes: [PreviewDebugMode] = [.none]
}
