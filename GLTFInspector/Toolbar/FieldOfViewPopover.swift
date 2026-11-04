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
                    Button("Use Perspective") { view.isOrthographic = false }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                } else {
                    DSSlider("Field of View", value: $view.fieldOfView, in: ViewState.fieldOfViewRange,
                             step: 1, reading: degrees)
                    HStack {
                        Spacer(minLength: DS.Spacing.m)
                        Button("Reset") { view.fieldOfView = ViewState.defaultFieldOfView }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
