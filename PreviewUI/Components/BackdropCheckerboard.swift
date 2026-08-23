import SwiftUI

/// The "None" swatch: checkerboard for *no* backdrop.
public struct BackdropCheckerboard: View {
    public var cell: CGFloat = 5

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.backdropWhite))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let square = CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(Path(square), with: .color(Theme.backdropChecker))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("default") {
    BackdropCheckerboard()
        .frame(width: PillMetrics.swatchSize, height: PillMetrics.swatchSize)
        .clipShape(.circle)
        .padding(24)
}
