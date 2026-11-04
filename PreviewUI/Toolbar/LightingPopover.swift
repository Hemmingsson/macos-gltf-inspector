import DesignSystem
import SwiftUI

/// The lighting chip and its popover: exposure · environment · tone mapping.
///
/// A popover rather than a menu because these are continuous values. A menu is for picking one of
/// n; dragging an exposure slider while watching the model is the whole point, and a menu closes
/// on the first click.
struct LightingPopover<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
        DSGlassPopoverButton(
            "Lighting",
            systemImage: "sun.max",
            help: "Lighting — exposure · environment · tone mapping"
        ) {
            LightingControls(viewport: viewport)
        }
    }
}

/// The popover's body. Split out so the chip stays about *presentation* and this stays about the
/// lighting values (exposure, environment, tone mapping).
struct LightingControls<Viewport: ViewportController>: View {
    var viewport: Viewport

    var body: some View {
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
                accessibilityLabel: "Environment rotation",
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
        }
    }
}

// MARK: - Previews

#Preview("controls", traits: .fixedLayout(width: 260, height: 160)) {
    @Previewable @State var viewport = MockViewportController(
        lighting: LightingSettings(exposure: 0.5, environmentRotationDegrees: 120)
    )
    PreviewCanvas(width: 260, background: .chrome) {
        LightingControls(viewport: viewport)
    }
}

#Preview("popover", traits: .fixedLayout(width: 400, height: 80)) {
    @Previewable @State var viewport = MockViewportController()
    PreviewCanvas(width: 400, height: 80, background: .canvas) {
        LightingPopover(viewport: viewport)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(DS.Spacing.xxl)
    }
}
