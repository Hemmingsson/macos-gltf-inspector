import DesignSystem
import SwiftUI

/// The lighting chip and its popover: exposure · environment · tone mapping · file-vs-studio.
///
/// A popover rather than a menu because these are continuous values. A menu is for picking one of
/// n; dragging an exposure slider while watching the model is the whole point, and a menu closes
/// on the first click.
public struct LightingPopover<Capabilities: Availability, Viewport: ViewportController>: View {
    public var availability: Capabilities
    public var viewport: Viewport

    public var body: some View {
        DSGlassPopoverButton(
            "Lighting",
            systemImage: "sun.max",
            help: "Lighting — exposure · environment · file vs studio"
        ) {
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
        DSPopoverPanel {
            DSSlider(
                "Exposure",
                value: PopoverControls.lighting(\.exposure, on: viewport),
                in: -3...3,
                step: 0.1,
                neutralValue: 0,
                reading: PopoverControls.exposureReading
            )

            DSSlider(
                "Environment",
                value: PopoverControls.lighting(\.environmentRotationDegrees, on: viewport),
                in: 0...360,
                step: 1,
                reading: PopoverControls.degreesReading
            )

            DSSegmentedPicker(
                "Environment",
                selection: PopoverControls.lighting(\.environment, on: viewport),
                options: StudioEnvironment.allCases
            ) { $0.title }

            // A glTF file carries no tone mapping, so this is the app's call and it belongs on
            // screen. Neutral is the review-oriented default; ACES is here because that is what
            // many DCC tools show, and matching what the author saw is half the job.
            DSMenuPicker(
                "Tone mapping",
                selection: PopoverControls.lighting(\.toneMapping, on: viewport),
                options: ToneMapping.allCases
            ) { $0.title }

            // Adaptive, per DESIGN.md: with no punctual lights in the file there is nothing to
            // switch *to*, so the control is absent rather than present-and-useless. The engine
            // still lights the model with the studio IBL either way.
            if availability.hasLights {
                DSSegmentedPicker(
                    "Lights",
                    selection: PopoverControls.lighting(\.usesFileLights, on: viewport),
                    options: [false, true]
                ) { $0 ? "File" : "Studio" }
            }
        }
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
        PreviewCanvas(width: 260, background: .chrome) {
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
            LightingPopover(
                availability: MockAvailability(hasLights: hasLights),
                viewport: viewport
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Spacing.xxl)
        }
    }
}

#Preview("controls studio", traits: .fixedLayout(width: 260, height: 160)) {
    LightingControlsPreviewHost(hasLights: false)
}

#Preview("controls file lights", traits: .fixedLayout(width: 260, height: 220)) {
    LightingControlsPreviewHost(hasLights: true)
}

#Preview("popover studio", traits: .fixedLayout(width: 400, height: 80)) {
    LightingPopoverPreviewHost(hasLights: false)
}

#Preview("popover file lights", traits: .fixedLayout(width: 400, height: 80)) {
    LightingPopoverPreviewHost(hasLights: true)
}
