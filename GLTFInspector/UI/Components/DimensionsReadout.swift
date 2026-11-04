import SwiftUI

/// Bottom-trailing W×H×D pill.
struct DimensionsReadout: View {
    var dimensions: Dimensions

    var body: some View {
        DSHUDCapsule(height: OverlayMetrics.dimensionsHeight) {
            Image(systemName: "cube")
                .font(DS.Font.callout)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(DS.Color.textSecondary)
                .accessibilityHidden(true)

            Text(label)
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dimensions")
        .accessibilityValue(label)
    }

    private var label: String {
        String(
            format: "%.2f × %.2f × %.2f m",
            dimensions.width,
            dimensions.height,
            dimensions.depth
        )
    }
}

private let sampleDimensions = Dimensions(width: 1.23, height: 0.45, depth: 2.10)
