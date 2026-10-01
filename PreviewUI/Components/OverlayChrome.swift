import DesignSystem
import SwiftUI


/// Shared numbers for the canvas-bottom overlays.
public enum OverlayMetrics {
    /// Inset of the bottom overlays from the canvas edge (`DS.Spacing.xl`).
    public static let inset = DS.Spacing.xl
    /// Dimensions pill height. Slightly under `DS.Metrics.glassControl` so the readout stays compact.
    public static let dimensionsHeight: CGFloat = 30
    /// Playback bar height. Taller than a glass control so the scrubber sits comfortably.
    public static let playbackHeight: CGFloat = 42
    /// Playback scrub track width in the wireframe.
    public static let scrubWidth: CGFloat = 250
    /// Orientation gizmo box (`width: 66; height: 66`).
    public static let orientationSize: CGFloat = 66
    /// X axis — `DS.Color.Axis.x`.
    public static let axisX = DS.Color.Axis.x
    /// Y axis — `DS.Color.Axis.y`.
    public static let axisY = DS.Color.Axis.y
    /// Z axis — `DS.Color.Axis.z`.
    public static let axisZ = DS.Color.Axis.z

    public static func strokeAxis(
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

    public static func drawAxisLabel(
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
