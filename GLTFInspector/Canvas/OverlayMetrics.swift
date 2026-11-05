import SwiftUI

/// Shared numbers for the canvas-bottom overlays.
enum OverlayMetrics {
    static let inset = DS.Spacing.xl
    /// Slightly under `DS.Metrics.glassControl` so the readout stays compact.
    static let dimensionsHeight: CGFloat = 30
    static let timelineHeight: CGFloat = DS.Metrics.glassControl
    static let navigationGizmoSize = DS.Metrics.navigationGizmoSize
    /// Hover name tag sits just clear of the pointer.
    static let tooltipOffset: CGFloat = 8

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
