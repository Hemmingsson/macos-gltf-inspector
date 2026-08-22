import SwiftUI

/// The camera lens chip and its popover: vertical field of view.
struct FieldOfViewPopover<Viewport: ViewportController>: View {
    var viewport: Viewport

    @State private var isPresented = false

    var body: some View {
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

struct FieldOfViewControls<Viewport: ViewportController>: View {
    var viewport: Viewport

    private let defaultFieldOfViewDegrees: Double = 35
    private let fieldOfViewRange: ClosedRange<Double> = 15...90

    var body: some View {
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
