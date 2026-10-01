import SwiftUI

/// The content column of a control popover (Lighting, Field of View).
///
/// Plain on purpose: **no background**. The system popover already draws its Liquid Glass; a fill
/// here would be glass-on-glass and kill the vibrancy that keeps `.primary` / `.secondary` text
/// crisp. The width is flexible — `DS.Metrics.popoverMinWidth` minimum, asking for
/// `DS.Metrics.popoverIdealWidth` — so a longer localisation or larger text size grows the popover
/// instead of clipping it, and height always fits the content.
public struct DSPopoverPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            content
        }
        .padding(DS.Spacing.xl)
        .frame(
            minWidth: DS.Metrics.popoverMinWidth,
            idealWidth: DS.Metrics.popoverIdealWidth,
            alignment: .leading
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Previews

private struct DSPopoverPanelPreview: View {
    @State private var exposure = 0.5
    @State private var rotation = 120.0
    @State private var usesFileLights = false
    @State private var isPresented = true

    var body: some View {
        Button("Lighting") { isPresented.toggle() }
            .padding(DS.Spacing.xxl)
            .frame(width: 360, height: 300, alignment: .top)
            .background(DS.Color.windowBackground)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                DSPopoverPanel {
                    DSSlider("Exposure", value: $exposure, in: -3...3, step: 0.1, neutralValue: 0) {
                        $0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
                    }
                    DSSlider("Environment", value: $rotation, in: 0...360, step: 1) {
                        $0.formatted(.number.precision(.fractionLength(0))) + "°"
                    }
                    DSSegmentedPicker("Lights", selection: $usesFileLights, options: [false, true]) {
                        $0 ? "File" : "Studio"
                    }
                }
            }
    }
}

#Preview("Popover panel") {
    DSPopoverPanelPreview()
}

#Preview("Popover panel inline, dark") {
    @Previewable @State var fov = 35.0
    DSPopoverPanel {
        DSSlider("Field of View", value: $fov, in: 15...90, step: 1) {
            $0.formatted(.number.precision(.fractionLength(0))) + "°"
        }
        HStack {
            Spacer()
            DSButton("Reset", size: .small) { fov = 35 }
        }
    }
    .background(DS.Color.windowBackground)
    .preferredColorScheme(.dark)
}

#Preview("Popover panel empty") {
    DSPopoverPanel {
        EmptyView()
    }
    .background(DS.Color.windowBackground)
}
