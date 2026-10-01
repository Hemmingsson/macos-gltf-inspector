import SwiftUI

/// Host-owned preview chrome bindings. Quick Look leaves `session` nil and
/// uses local `@State` in `PreviewScene` instead. The host builds these from `PreviewSession.bindings`.
public struct PreviewSessionBindings {
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
    /// Look / view-mode cycle index into `PreviewScene.debugModes` (host pills).
    var debugModeIndex: Binding<Int>

    public init(
        autoRotate: Binding<Bool>,
        showFloor: Binding<Bool>,
        backdropIndex: Binding<Int>,
        centerModel: Binding<Bool>,
        orthographic: Binding<Bool>,
        exposureEV: Binding<Float>,
        dimStudioForFileLights: Binding<Bool>,
        environmentYaw: Binding<Float>,
        doubleSided: Binding<Bool>,
        showSkeleton: Binding<Bool>,
        fieldOfViewDegrees: Binding<Float>,
        debugModeIndex: Binding<Int>
    ) {
        self.autoRotate = autoRotate
        self.showFloor = showFloor
        self.backdropIndex = backdropIndex
        self.centerModel = centerModel
        self.orthographic = orthographic
        self.exposureEV = exposureEV
        self.dimStudioForFileLights = dimStudioForFileLights
        self.environmentYaw = environmentYaw
        self.doubleSided = doubleSided
        self.showSkeleton = showSkeleton
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.debugModeIndex = debugModeIndex
    }
}
