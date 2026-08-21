import SwiftUI

/// Shell-only Debug menu content. Reads the key window's `MockScene` through `FocusedValues`.
struct DebugMenuCommands: View {
    @FocusedValue(\.mockScene) private var mockScene

    var body: some View {
        if let mockScene {
            DebugMenuBody(mock: mockScene)
        } else {
            Text("No focused window")
                .disabled(true)
        }
    }
}

/// `@Bindable` lives here so `Toggle` can write the focused `@Observable` mock.
private struct DebugMenuBody: View {
    @Bindable var mock: MockScene

    var body: some View {
        Toggle("Validation warnings", isOn: $mock.hasValidationWarnings)
        Toggle("Multiple scenes", isOn: $mock.hasMultipleScenes)
        Toggle("Animations", isOn: $mock.hasAnimations)
        Toggle("Lights", isOn: $mock.hasLights)
        Toggle("Cameras", isOn: $mock.hasCameras)
        Toggle("Skin / morphs", isOn: skinMorphs)
        Toggle("Missing material channels", isOn: $mock.hasMissingChannels)
        Toggle("Uncentered (origin gizmo)", isOn: $mock.isUncentered)
        Divider()
        Button("Preset: Plain mesh") { mock.apply(.plainMesh) }
        Button("Preset: Rigged + animated") { mock.apply(.riggedAnimated) }
        Button("Preset: Invalid file") { mock.apply(.invalidFile) }
        Divider()
        Button("State: Empty") { mock.documentState = .empty }
        Button("State: Loading") { mock.documentState = .loading }
        Button("State: Ready") { mock.documentState = .ready }
        Button("State: Failed") {
            mock.documentState = .failed(ShellStatusCopy.invalidFileDetail)
        }
    }

    /// Plan / card name one switch; the mock keeps skin and morphs as separate flags for §2.
    private var skinMorphs: Binding<Bool> {
        Binding(
            get: { mock.hasSkin || mock.hasMorphs },
            set: { on in
                mock.hasSkin = on
                mock.hasMorphs = on
            }
        )
    }
}
