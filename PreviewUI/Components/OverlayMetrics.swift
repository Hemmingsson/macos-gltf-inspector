import DesignSystem
import SwiftUI


/// Shared numbers for the canvas-bottom overlays.
enum OverlayMetrics {
    static let inset = DS.Spacing.xl
    /// Slightly under `DS.Metrics.glassControl` so the readout stays compact.
    static let dimensionsHeight: CGFloat = 30
    /// Taller than a glass control so the scrubber sits comfortably.
    static let playbackHeight: CGFloat = 42
    static let scrubWidth: CGFloat = 250
    static let orientationSize: CGFloat = 66

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

    static func drawAxisLabel(
        _ context: GraphicsContext,
        _ text: String,
        at point: CGPoint,
        color: Color,
        size: CGFloat = 9
    ) {
        context.draw(
            Text(text)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color),
            at: point,
            anchor: .topLeading
        )
    }
}
