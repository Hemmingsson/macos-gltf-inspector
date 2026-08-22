import SwiftUI

/// Bottom-trailing W×H×D pill.
struct DimensionsReadout: View {
    var dimensions: Dimensions

    var body: some View {
        OverlayChrome(height: OverlayMetrics.dimensionsHeight, cornerRadius: OverlayMetrics.dimensionsRadius) {
            Image(systemName: "cube")
                .font(.system(size: 12, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.text2)
                .accessibilityHidden(true)

            Text(label)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.glyph)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dimensions")
        .accessibilityValue(label)
    }

    private var label: String {
        String(
            format: "%.2f × %.2f × %.2f %@",
            dimensions.width,
            dimensions.height,
            dimensions.depth,
            dimensions.unit
        )
    }
}
