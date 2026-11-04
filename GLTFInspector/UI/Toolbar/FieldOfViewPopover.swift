import SwiftUI

/// The camera lens chip and its popover: vertical field of view.
struct FieldOfViewPopover: View {
    @Bindable var view: ViewState

    var body: some View {
        DSGlassPopoverButton(
            "Field of view",
            systemImage: "camera.aperture",
            value: degrees(view.fieldOfView),
            help: "Field of view — \(degrees(view.fieldOfView))"
        ) {
            DSPopoverPanel {
                if view.isOrthographic {
                    DSButton("Use Perspective", variant: .prominent, size: .small) { view.isOrthographic = false }
                } else {
                    DSSlider("Field of View", value: $view.fieldOfView, in: ViewState.fieldOfViewRange,
                             step: 1, reading: degrees)
                    HStack {
                        Spacer(minLength: DS.Spacing.m)
                        DSButton("Reset", size: .small) { view.fieldOfView = ViewState.defaultFieldOfView }
                    }
                }
            }
        }
    }
}
