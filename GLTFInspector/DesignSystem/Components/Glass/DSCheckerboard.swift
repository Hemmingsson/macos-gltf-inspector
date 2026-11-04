import SwiftUI

/// The "no backdrop" checkerboard: `DS.Color.Backdrop.checker` squares on
/// `DS.Color.Backdrop.white`.
///
/// Fixed colours on purpose — the checkerboard means *transparent*, and reads that way only as
/// light grey on white in either appearance. Fills whatever frame it is given; clip it to the
/// shape you need (a swatch clips it to a circle). Decorative, so hidden from accessibility.
struct DSCheckerboard: View {
    /// Side of one square.
    var cell: CGFloat

    init(cell: CGFloat = DS.Metrics.checkerboardCell) {
        self.cell = cell
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(DS.Color.Backdrop.white))
            let columns = Int((size.width / cell).rounded(.up))
            let rows = Int((size.height / cell).rounded(.up))
            var squares = Path()
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    squares.addRect(CGRect(
                        x: CGFloat(column) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    ))
                }
            }
            context.fill(squares, with: .color(DS.Color.Backdrop.checker))
        }
        .accessibilityHidden(true)
    }
}
