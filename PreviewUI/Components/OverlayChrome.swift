import SwiftUI

/// Shared numbers for the canvas-bottom overlays.
public enum OverlayMetrics {
    /// `bottom: 16px; left/right: 16px`.
    public static let inset: CGFloat = 16
    /// Dimensions pill `height: 30px`.
    public static let dimensionsHeight: CGFloat = 30
    /// Dimensions pill `border-radius: 9px`.
    public static let dimensionsRadius: CGFloat = 9
    /// Playback bar `height: 42px`.
    public static let playbackHeight: CGFloat = 42
    /// Playback bar `border-radius: 13px`.
    public static let playbackRadius: CGFloat = 13
    /// Playback scrub track width in the wireframe.
    public static let scrubWidth: CGFloat = 250
    /// Orientation gizmo box (`width: 66; height: 66`).
    public static let orientationSize: CGFloat = 66
    /// Conventional RGB axis colours (not Theme tokens — they mean X/Y/Z, not glTF kinds).
    public static let axisX = Color(red: 0xE2 / 255, green: 0x56 / 255, blue: 0x4A / 255)
    public static let axisY = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    public static let axisZ = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)

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

/// Flat / glass chrome for a bottom overlay pill (dimensions, playback).
public struct OverlayChrome<Content: View>: View {
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var horizontalPadding: CGFloat = 12
    @ViewBuilder public var content: () -> Content

    public var body: some View {
        cluster
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    private var cluster: some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("dimensions slot") {
    OverlayChrome(
        height: OverlayMetrics.dimensionsHeight,
        cornerRadius: OverlayMetrics.dimensionsRadius
    ) {
        Image(systemName: "cube")
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
        Text("1.00 × 1.00 × 1.00 m")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.glyph)
    }
    .padding(24)
}

#Preview("playback slots") {
    OverlayChrome(
        height: OverlayMetrics.playbackHeight,
        cornerRadius: OverlayMetrics.playbackRadius,
        horizontalPadding: 14
    ) {
        Text("Idle")
            .font(.system(size: 12))
            .foregroundStyle(Theme.glyph)
        Theme.hair
            .frame(width: Theme.hairlineWidth, height: 20)
        PlaybackPlayButton(isPlaying: false) {}
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Theme.controlFill)
            .frame(width: OverlayMetrics.scrubWidth, height: 4)
        Text("00:00 / 00:02")
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(Theme.text2)
    }
    .padding(24)
}
