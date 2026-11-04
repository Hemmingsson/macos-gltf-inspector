import SwiftUI

/// Bottom-trailing W×H×D pill.
struct DimensionsReadout: View {
    var size: SIMD3<Float>

    var body: some View {
        DSHUDCapsule(height: OverlayMetrics.dimensionsHeight) {
            Image(systemName: "cube")
                .font(.callout)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(label)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dimensions")
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

