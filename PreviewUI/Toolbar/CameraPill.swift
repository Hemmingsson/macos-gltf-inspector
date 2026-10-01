import DesignSystem
import SwiftUI

/// Trailing **Camera** cluster — where you stand and how you move.
///
/// One `DSGlassCluster`: auto-rotate, center, orthographic, FoV, Fit, presets. Each control
/// draws its own glass; nothing is nested glass-on-glass.
public struct CameraPill<Viewport: ViewportController>: View {
    public var viewport: Viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        DSGlassCluster {
            DSGlassToggleButton(
                "Auto-rotate",
                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                isOn: autoRotate
            )
            .disabled(reduceMotion)

            DSGlassToggleButton("Center Model", systemImage: "dot.scope", isOn: center)

            DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: orthographic)

            FieldOfViewPopover(viewport: viewport)

            DSGlassIconButton("Fit", systemImage: "viewfinder") {
                viewport.fit()
            }

            CameraPresetMenu(viewport: viewport)
        }
    }

    /// Reduce Motion parks the toggle off even if the session flag is still set.
    private var autoRotate: Binding<Bool> {
        Binding(
            get: { viewport.autoRotates && !reduceMotion },
            set: { newValue in
                guard !reduceMotion else { return }
                viewport.setAutoRotate(newValue)
            }
        )
    }

    private var center: Binding<Bool> {
        Binding(
            get: { viewport.isCentered },
            set: { viewport.setCenter($0) }
        )
    }

    private var orthographic: Binding<Bool> {
        Binding(
            get: { viewport.projection == .orthographic },
            set: { viewport.setProjection($0 ? .orthographic : .perspective) }
        )
    }
}

/// Canned angles — Front · Back · Left · Right · Top · Bottom · Isometric.
///
/// Shortcuts come from `DS.Shortcuts.cameraPreset` (⌥⌘ + digits) so they cannot collide with
/// view mode (⌘1 / ⌘2). The old un-modified digit shortcuts are gone from this picker.
public struct CameraPresetMenu<Viewport: ViewportController>: View {
    public var viewport: Viewport

    public var body: some View {
        DSGlassMenuButton(
            "Camera preset",
            systemImage: "cube",
            isEngaged: viewport.activeCameraPreset != nil,
            help: "Camera presets — Front · Top · Isometric…"
        ) {
            DSInlineMenuPicker("Camera preset", selection: preset) {
                ForEach(CameraPreset.allCases) { preset in
                    Text(preset.title)
                        .tag(Optional(preset))
                        .keyboardShortcutIfAvailable(cameraPresetShortcut(for: preset))
                }
            }
        }
        .accessibilityValue(viewport.activeCameraPreset?.title ?? "Custom")
    }

    private var preset: Binding<CameraPreset?> {
        Binding(
            get: { viewport.activeCameraPreset },
            set: { newValue in
                guard let newValue else { return }
                viewport.applyCameraPreset(newValue)
            }
        )
    }

    private func cameraPresetShortcut(for preset: CameraPreset) -> KeyboardShortcut? {
        DS.Shortcuts.CameraPreset(rawValue: preset.rawValue)
            .flatMap { DS.Shortcuts.cameraPreset($0) }
    }
}

// MARK: - Previews

private struct CameraPillPreviewHost: View {
    @State private var viewport: MockViewportController

    init(viewport: MockViewportController) {
        _viewport = State(initialValue: viewport)
    }

    var body: some View {
        PreviewCanvas(width: 420, height: 64, background: .canvas) {
            CameraPill(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, DS.Spacing.canvasInset)
        }
    }
}

#Preview("default", traits: .fixedLayout(width: 420, height: 64)) {
    CameraPillPreviewHost(viewport: MockViewportController())
}

#Preview("orthographic", traits: .fixedLayout(width: 420, height: 64)) {
    CameraPillPreviewHost(viewport: MockViewportController(projection: .orthographic))
}

#Preview("auto-rotate", traits: .fixedLayout(width: 420, height: 64)) {
    CameraPillPreviewHost(viewport: MockViewportController(autoRotates: true))
}

#Preview("preset front", traits: .fixedLayout(width: 420, height: 64)) {
    CameraPillPreviewHost(viewport: MockViewportController(activeCameraPreset: .front))
}
