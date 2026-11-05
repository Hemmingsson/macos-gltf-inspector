import SwiftUI

/// The camera lens chip and its popover: vertical field of view.
struct FieldOfViewPopover: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassPopoverButton(
            "Field of view",
            value: degrees(view.fieldOfView),
            help: "Field of view — \(degrees(view.fieldOfView))"
        ) {
            DSPopoverPanel {
                DSSlider("Field of View", value: $view.fieldOfView, in: ViewState.fieldOfViewRange,
                         step: 1, reading: degrees)
            }
        }
    }
}
