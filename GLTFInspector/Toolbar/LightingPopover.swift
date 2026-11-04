import GLTFCore
import SwiftUI

/// The lighting chip and its popover: exposure · environment · tone mapping. A popover rather
/// than a menu because these are continuous values watched while dragging.
struct LightingPopover: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassPopoverButton(
            "Lighting",
            systemImage: "sun.max",
            help: "Lighting — exposure · environment · tone mapping"
        ) {
            DSPopoverPanel {
                DSSlider("Exposure", value: $view.exposure, in: -3...3, step: 0.1, neutralValue: 0,
                         reading: { $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV" })
                DSSlider("Environment", value: $view.environmentYaw, in: 0...360, step: 1,
                         accessibilityLabel: "Environment rotation", reading: degrees)
                DSPicker("Environment", selection: $view.environment,
                         options: LightingEnvironment.allCases, style: .segmented) { $0.title }
                // A glTF file carries no tone mapping, so this is the app's call and it belongs
                // on screen.
                DSPicker("Tone mapping", selection: $view.toneMapping,
                         options: RenderLook.ToneMapping.allCases, style: .menu) { $0.title }
            }
        }
    }
}

func degrees(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0))) + "°"
}
