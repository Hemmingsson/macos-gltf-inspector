import SwiftUI

/// Bottom-trailing W×H×D pill.
struct DimensionsReadout: View {
    var size: SIMD3<Float>
    /// The selected node the size belongs to; nil for the whole model.
    var name: String?

    var body: some View {
        DSHUDCapsule(height: OverlayMetrics.dimensionsHeight) {
            Image(systemName: "cube")
                .font(.callout)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if let name {
                Text(name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(label)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name.map { "Dimensions of \($0)" } ?? "Dimensions")
        .accessibilityValue(label)
    }

    private var label: String {
        String(
            format: "%.2f × %.2f × %.2f m",
            size.x,
            size.y,
            size.z
        )
    }
}

