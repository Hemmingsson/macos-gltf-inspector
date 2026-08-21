import SwiftUI

/// Shared numbers for the canvas-bottom overlays, from `Main-html/Main.dc.html`.
enum OverlayMetrics {
    /// `bottom: 16px; left/right: 16px`.
    static let inset: CGFloat = 16
    /// Dimensions pill `height: 30px`.
    static let dimensionsHeight: CGFloat = 30
    /// Dimensions pill `border-radius: 9px`.
    static let dimensionsRadius: CGFloat = 9
    /// Playback bar `height: 42px`.
    static let playbackHeight: CGFloat = 42
    /// Playback bar `border-radius: 13px`.
    static let playbackRadius: CGFloat = 13
    /// Playback scrub track width in the wireframe.
    static let scrubWidth: CGFloat = 250
    /// Orientation gizmo box (`width: 66; height: 66`).
    static let orientationSize: CGFloat = 66
    /// Conventional RGB axis colours (not Theme tokens — they mean X/Y/Z, not glTF kinds).
    static let axisX = Color(red: 0xE2 / 255, green: 0x56 / 255, blue: 0x4A / 255)
    static let axisY = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    static let axisZ = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)

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

/// Flat / glass chrome for a bottom overlay pill (dimensions, playback).
///
/// Same flatten switch as the toolbar pills: offscreen `.glassEffect` cannot sample a backdrop,
/// so the snapshot harness substitutes a card fill.
struct OverlayChrome<Content: View>: View {
    var height: CGFloat
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat = 12
    @ViewBuilder var content: () -> Content
    @Environment(\.previewFlattenGlass) private var flattenGlass
    @Environment(\.previewBorder) private var border

    var body: some View {
        if flattenGlass {
            cluster
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.card)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(border, lineWidth: Theme.hairlineWidth)
                }
        } else {
            cluster
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        }
    }

    private var cluster: some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
    }
}
