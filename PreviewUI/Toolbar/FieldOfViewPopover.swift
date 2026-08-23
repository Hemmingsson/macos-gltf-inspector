import SwiftUI

/// The camera lens chip and its popover: vertical field of view.
public struct FieldOfViewPopover<Viewport: ViewportController>: View {
    public var viewport: Viewport

    @State private var isPresented = false

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            PillMenuLabel(symbol: "camera.aperture", isExpanded: isPresented)
        }
        .buttonStyle(.plain)
        .help("Field of view — \(currentReading)")
        .accessibilityLabel("Field of view")
        .accessibilityValue(currentReading)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FieldOfViewControls(viewport: viewport)
        }
    }

    private var currentReading: String {
        String(format: "%.0f°", viewport.fieldOfViewDegrees)
    }
}

public struct FieldOfViewControls<Viewport: ViewportController>: View {
    public var viewport: Viewport

    private let defaultFieldOfViewDegrees: Double = 35
    private let fieldOfViewRange: ClosedRange<Double> = 15...90

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            slider(
                "Field of View",
                value: binding,
                range: fieldOfViewRange,
                reading: String(format: "%.0f°", viewport.fieldOfViewDegrees)
            )
            .disabled(viewport.projection == .orthographic)

            HStack {
                if viewport.projection == .orthographic {
                    Text("Perspective only")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }

                Spacer(minLength: 8)

                Button("Reset") {
                    viewport.setFieldOfViewDegrees(Float(defaultFieldOfViewDegrees))
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

    private var binding: Binding<Double> {
        Binding(
            get: { Double(viewport.fieldOfViewDegrees) },
            set: { viewport.setFieldOfViewDegrees(Float($0)) }
        )
    }
}

// MARK: - Previews

private struct FieldOfViewControlsPreviewHost: View {
    var projection: Projection
    @State private var viewport: MockViewportController

    init(projection: Projection) {
        self.projection = projection
        _viewport = State(
            initialValue: MockViewportController(
                projection: projection,
                fieldOfViewDegrees: 45
            )
        )
    }

    var body: some View {
        PreviewCanvas(width: 250, background: .chrome) {
            FieldOfViewControls(viewport: viewport)
        }
    }
}

private struct FieldOfViewPopoverPreviewHost: View {
    var projection: Projection
    @State private var viewport: MockViewportController

    init(projection: Projection) {
        self.projection = projection
        _viewport = State(
            initialValue: MockViewportController(
                projection: projection,
                fieldOfViewDegrees: 45
            )
        )
    }

    var body: some View {
        PreviewCanvas(width: 400, height: 80, background: .canvas) {
            Pill(circle: true) {
                FieldOfViewPopover(viewport: viewport)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}

#Preview("controls perspective", traits: .fixedLayout(width: 250, height: 120)) {
    FieldOfViewControlsPreviewHost(projection: .perspective)
}

#Preview("controls orthographic", traits: .fixedLayout(width: 250, height: 120)) {
    FieldOfViewControlsPreviewHost(projection: .orthographic)
}

#Preview("popover perspective", traits: .fixedLayout(width: 400, height: 80)) {
    FieldOfViewPopoverPreviewHost(projection: .perspective)
}

#Preview("popover orthographic", traits: .fixedLayout(width: 400, height: 80)) {
    FieldOfViewPopoverPreviewHost(projection: .orthographic)
}
