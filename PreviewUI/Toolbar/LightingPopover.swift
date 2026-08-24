import SwiftUI

/// The lighting chip and its popover: exposure · environment · tone mapping · file-vs-studio.
///
/// A popover rather than a menu because these are continuous values. A menu is for picking one of
/// n; dragging an exposure slider while watching the model is the whole point, and a menu closes
/// on the first click.
public struct LightingPopover<Capabilities: Availability, Viewport: ViewportController>: View {
    public var availability: Capabilities
    public var viewport: Viewport

    @State private var isPresented = false

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            PillMenuLabel(symbol: "sun.max", isExpanded: isPresented)
        }
        .buttonStyle(.plain)
        .help("Lighting — exposure · environment · file vs studio")
        .accessibilityLabel("Lighting")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LightingControls(availability: availability, viewport: viewport)
        }
    }
}

/// The popover's body. Split out so the chip stays about *presentation* and this stays about the
/// three values, which is also what makes it easy to host alone in Debug fixtures.
public struct LightingControls<Capabilities: Availability, Viewport: ViewportController>: View {
    public var availability: Capabilities
    public var viewport: Viewport

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider(
                "Exposure",
                value: setting(\.exposure),
                range: -3...3,
                reading: String(format: "%+.1f EV", viewport.lighting.exposure)
            )

            slider(
                "Environment",
                value: setting(\.environmentRotationDegrees),
                range: 0...360,
                reading: String(format: "%.0f°", viewport.lighting.environmentRotationDegrees)
            )

            VStack(alignment: .leading, spacing: 6) {
                label("Environment")
                Picker("Environment", selection: setting(\.environment)) {
                    ForEach(StudioEnvironment.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // A glTF file carries no tone mapping, so this is the app's call and it belongs on
            // screen. Neutral is the review-oriented default; ACES is here because that is what
            // many DCC tools show, and matching what the author saw is half the job.
            VStack(alignment: .leading, spacing: 6) {
                label("Tone mapping")
                Picker("Tone mapping", selection: setting(\.toneMapping)) {
                    ForEach(ToneMapping.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // Adaptive, per DESIGN.md: with no punctual lights in the file there is nothing to
            // switch *to*, so the control is absent rather than present-and-useless. The engine
            // still lights the model with the studio IBL either way.
            if availability.hasLights {
                VStack(alignment: .leading, spacing: 6) {
                    label("Lights")
                    Picker("Lights", selection: setting(\.usesFileLights)) {
                        Text("Studio").tag(false)
                        Text("File").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .padding(16)
        .frame(width: 250)
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        reading: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                label(title)
                Spacer(minLength: 8)
                Text(reading)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.text2)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(Theme.accent)
                .accessibilityLabel(title)
                .accessibilityValue(reading)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Theme.text2)
    }

    // `LightingSettings` is one value on the seam, not four properties, so every edit reads the
    // current struct, changes one field and hands the whole thing back. That keeps the controller
    // free to react to a lighting change once instead of four times.
    private func setting<Value>(_ field: WritableKeyPath<LightingSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewport.lighting[keyPath: field] },
            set: { newValue in
                var lighting = viewport.lighting
                lighting[keyPath: field] = newValue
                viewport.setLighting(lighting)
            }
        )
    }
}

// MARK: - Previews

private struct LightingControlsPreviewHost: View {
    var hasLights: Bool
    @State private var viewport: MockViewportController

    init(hasLights: Bool) {
        self.hasLights = hasLights
        _viewport = State(
            initialValue: MockViewportController(
                lighting: LightingSettings(
                    exposure: 0.5,
                    environmentRotationDegrees: 120,
                    usesFileLights: false,
                    usesStudioEnvironment: true
                )
            )
        )
    }

    var body: some View {
        PreviewCanvas(width: 250, background: .chrome) {
            LightingControls(
                availability: MockAvailability(hasLights: hasLights),
                viewport: viewport
            )
        }
    }
}

private struct LightingPopoverPreviewHost: View {
    var hasLights: Bool
    @State private var viewport: MockViewportController

    init(hasLights: Bool) {
        self.hasLights = hasLights
        _viewport = State(initialValue: MockViewportController())
    }

    var body: some View {
        PreviewCanvas(width: 400, height: 80, background: .canvas) {
            Pill(circle: true) {
                LightingPopover(
                    availability: MockAvailability(hasLights: hasLights),
                    viewport: viewport
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}

#Preview("controls studio", traits: .fixedLayout(width: 250, height: 160)) {
    LightingControlsPreviewHost(hasLights: false)
}

#Preview("controls file lights", traits: .fixedLayout(width: 250, height: 220)) {
    LightingControlsPreviewHost(hasLights: true)
}

#Preview("popover studio", traits: .fixedLayout(width: 400, height: 80)) {
    LightingPopoverPreviewHost(hasLights: false)
}

#Preview("popover file lights", traits: .fixedLayout(width: 400, height: 80)) {
    LightingPopoverPreviewHost(hasLights: true)
}
