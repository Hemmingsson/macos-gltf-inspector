import SwiftUI

/// Shared numbers for the canvas-bottom overlays.
enum OverlayMetrics {
    static let inset = DS.Spacing.xl
    /// Slightly under `DS.Metrics.glassControl` so the readout stays compact.
    static let dimensionsHeight: CGFloat = 30
    static let navigationGizmoSize = DS.Metrics.navigationGizmoSize
    /// Hover name tag: compact, offset so the pointer never covers it.
    static let tooltipHeight: CGFloat = 24
    static let tooltipOffset: CGFloat = 14

    static func strokeAxis(
        _ context: GraphicsContext,
        from: CGPoint,
        to: CGPoint,
        color: Color,
        lineWidth: CGFloat = 2
    ) {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }


}
