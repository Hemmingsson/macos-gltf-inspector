import DesignSystem
import SwiftUI

/// Bottom-trailing W×H×D pill.
public struct DimensionsReadout: View {
    public var dimensions: Dimensions

    public var body: some View {
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
            format: "%.2f × %.2f × %.2f %@",
            dimensions.width,
            dimensions.height,
            dimensions.depth,
            dimensions.unit
        )
    }
}

// MARK: - Previews

private let sampleDimensions = Dimensions(width: 1.23, height: 0.45, depth: 2.10)

#Preview("centered", traits: .fixedLayout(width: 400, height: 200)) {
    PreviewCanvas(width: 400, height: 200, background: .canvas) {
        DimensionsReadout(dimensions: sampleDimensions)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("off-center", traits: .fixedLayout(width: 400, height: 200)) {
    PreviewCanvas(width: 400, height: 200, background: .canvas) {
        DimensionsReadout(dimensions: sampleDimensions)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(OverlayMetrics.inset)
    }
}
