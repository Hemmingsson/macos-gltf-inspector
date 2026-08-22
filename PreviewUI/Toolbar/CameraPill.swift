import SwiftUI

/// Trailing **Camera** cluster — where you stand and how you move.
///
/// Sketch-style islands: only tightly related controls share glass. Framing toggles
/// (auto-rotate · center) share one stadium; projection, Fit, and presets each get their
/// own circle.
struct CameraPill<Viewport: ViewportController>: View {
    var viewport: Viewport
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var autoRotateOn: Bool {
        viewport.autoRotates && !reduceMotion
    }

    private var isOrthographic: Bool {
        viewport.projection == .orthographic
    }

    var body: some View {
        HStack(spacing: PillMetrics.islandSpacing) {
            FramingIsland(
                autoRotateOn: autoRotateOn,
                reduceMotion: reduceMotion,
                isCentered: viewport.isCentered,
                onToggleAutoRotate: {
                    guard !reduceMotion else { return }
                    viewport.setAutoRotate(!viewport.autoRotates)
                },
                onToggleCenter: { viewport.setCenter(!viewport.isCentered) }
            )

            Pill(circle: true) {
                PillButton(
                    symbol: "perspective",
                    title: isOrthographic ? "Perspective" : "Orthographic",
                    isOn: isOrthographic
                ) {
                    viewport.setProjection(isOrthographic ? .perspective : .orthographic)
                }
            }

            Pill(circle: true) {
                PillButton(symbol: "viewfinder", title: "Fit") {
                    viewport.fit()
                }
            }

            Pill(circle: true) {
                CameraPresetMenu(viewport: viewport)
            }
        }
    }
}

/// Auto-rotate + center — one “how the model sits in frame” pair.
private struct FramingIsland: View {
    var autoRotateOn: Bool
    var reduceMotion: Bool
    var isCentered: Bool
    var onToggleAutoRotate: () -> Void
    var onToggleCenter: () -> Void

    var body: some View {
        // Two discrete circles, not a merged stadium — every camera control reads as its own button.
        Group {
            Pill(circle: true) {
                PillButton(
                    symbol: "arrow.trianglehead.counterclockwise.rotate.90",
                    title: reduceMotion
                        ? "Auto-rotate (unavailable with Reduce Motion)"
                        : "Auto-rotate",
                    isOn: autoRotateOn,
                    action: onToggleAutoRotate
                )
            }

            Pill(circle: true) {
                PillButton(
                    symbol: "dot.scope",
                    title: isCentered ? "Show authored origin" : "Center model",
                    isOn: isCentered,
                    action: onToggleCenter
                )
            }
        }
    }
}

/// Canned angles — Front · Back · Left · Right · Top · Bottom · Isometric.
struct CameraPresetMenu<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
        Menu {
            Picker("Camera preset", selection: preset) {
                ForEach(CameraPreset.allCases) { preset in
                    Text(preset.title).tag(Optional(preset))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "cube")
                .font(.system(size: PillMetrics.glyphSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(viewport.activeCameraPreset != nil ? Theme.selectionText : Theme.glyph)
                .frame(width: PillMetrics.buttonSize, height: PillMetrics.buttonSize)
                .background {
                    if viewport.activeCameraPreset != nil {
                        Circle()
                            .fill(Theme.selection)
                            .padding(PillMetrics.toggleWashInset)
                    }
                }
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Camera presets — Front · Top · Isometric…")
        .accessibilityLabel("Camera preset")
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
}
