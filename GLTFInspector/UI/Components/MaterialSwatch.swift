import SwiftUI

/// Small colour tile for material factor readouts and map thumbnails.
struct MaterialSwatch: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        shape
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
            }
            .accessibilityHidden(true)
    }
}
