import DesignSystem
import SwiftUI


/// Shared numbers for the canvas-bottom overlays.
public enum OverlayMetrics {
    /// Inset of the bottom overlays from the canvas edge (`DS.Spacing.xl`).
    public static let inset = DS.Spacing.xl
    /// Dimensions pill height. Slightly under `DS.Metrics.glassControl` so the readout stays compact.
    public static let dimensionsHeight: CGFloat = 30
    /// Legacy rounded-rect radius; HUDs now use `DSHUDCapsule` (capsule). Kept for Phase 2 callers.
    public static let dimensionsRadius: CGFloat = 9
    /// Playback bar height. Taller than a glass control so the scrubber sits comfortably.
    public static let playbackHeight: CGFloat = 42
    /// Legacy rounded-rect radius; HUDs now use `DSHUDCapsule` (capsule). Kept for Phase 2 callers.
    public static let playbackRadius: CGFloat = 13
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

/// Thin wrapper over `DSHUDCapsule` for the dimensions / playback HUD slot.
public struct OverlayChrome<Content: View>: View {
    public var height: CGFloat
    /// Ignored — `DSHUDCapsule` is a capsule. Kept so Phase 2 callers still compile.
    public var cornerRadius: CGFloat = 0
    public var horizontalPadding: CGFloat = DS.Spacing.l
    @ViewBuilder public var content: () -> Content

    public var body: some View {
        let _ = cornerRadius
        DSHUDCapsule(height: height, horizontalPadding: horizontalPadding) {
            content()
        }
    }
}

// MARK: - Previews

#Preview("dimensions slot") {
    OverlayChrome(height: OverlayMetrics.dimensionsHeight) {
        Image(systemName: "cube")
            .font(DS.Font.callout)
            .foregroundStyle(DS.Color.textSecondary)
        Text("1.00 × 1.00 × 1.00 m")
            .font(DS.Font.value)
            .foregroundStyle(DS.Color.textPrimary)
    }
    .padding(DS.Spacing.xxl)
}

#Preview("playback slots") {
    OverlayChrome(
        height: OverlayMetrics.playbackHeight,
        horizontalPadding: DS.Spacing.l
    ) {
        Text("Idle")
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.textPrimary)
        DSGlassIslandDivider()
        PlaybackPlayButton(isPlaying: false) {}
        DSHUDSlider(value: .constant(0.25), in: 0...1, accessibilityLabel: "Playhead")
            .controlSize(.small)
            .frame(width: OverlayMetrics.scrubWidth)
        Text("00:00 / 00:02")
            .font(DS.Font.value)
            .foregroundStyle(DS.Color.textSecondary)
    }
    .padding(DS.Spacing.xxl)
}
