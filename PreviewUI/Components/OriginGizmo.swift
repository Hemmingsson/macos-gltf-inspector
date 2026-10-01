import DesignSystem
import SwiftUI

/// World-origin axes shown on the canvas when Center is off, or when the file has a non-zero
/// authored origin. Drawn as a triad at the computed origin, with the authored origin on its tag.
public struct OriginGizmo: View {
    /// Authored origin relative to the model, in metres — shown on the tag.
    public var authoredOrigin: Vector3

    public var body: some View {
        GeometryReader { geo in
            let origin = Self.origin(in: geo.size)
            ZStack {
                Canvas { context, _ in
                    OverlayMetrics.strokeAxis(
                        context,
                        from: origin,
                        to: CGPoint(x: origin.x + 54, y: origin.y),
                        color: OverlayMetrics.axisX,
                        lineWidth: 2.2
                    )
                    OverlayMetrics.strokeAxis(
                        context,
                        from: origin,
                        to: CGPoint(x: origin.x, y: origin.y - 60),
                        color: OverlayMetrics.axisY,
                        lineWidth: 2.2
                    )
                    OverlayMetrics.strokeAxis(
                        context,
                        from: origin,
                        to: CGPoint(x: origin.x - 34, y: origin.y + 18),
                        color: OverlayMetrics.axisZ,
                        lineWidth: 2.2
                    )

                    OverlayMetrics.drawAxisLabel(
                        context, "X",
                        at: CGPoint(x: origin.x + 58, y: origin.y + 4),
                        color: OverlayMetrics.axisX,
                        size: 11
                    )
                    OverlayMetrics.drawAxisLabel(
                        context, "Y",
                        at: CGPoint(x: origin.x - 6, y: origin.y - 64),
                        color: OverlayMetrics.axisY,
                        size: 11
                    )
                    OverlayMetrics.drawAxisLabel(
                        context, "Z",
                        at: CGPoint(x: origin.x - 54, y: origin.y + 26),
                        color: OverlayMetrics.axisZ,
                        size: 11
                    )
                }
                .allowsHitTesting(false)

                Circle()
                    .fill(DS.Color.textTertiary)
                    .frame(width: 6, height: 6)
                    .position(origin)

                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: .topTrailing) {
                        DSHUDCapsule(
                            height: DS.Spacing.xxl,
                            horizontalPadding: DS.Spacing.m
                        ) {
                            Text(tag)
                                .font(DS.Font.micro)
                                .foregroundStyle(DS.Color.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.top, DS.Spacing.s)
                        .padding(.trailing, DS.Spacing.s)
                    }
                    .position(origin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Origin gizmo")
        .accessibilityValue(tag)
    }

    /// Hub of the triad: centred horizontally, slightly below mid-canvas so Y has room to rise.
    private static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: size.height * 0.58)
    }

    private var tag: String {
        String(
            format: "authored origin (%.2f, %.2f, %.2f)",
            authoredOrigin.x,
            authoredOrigin.y,
            authoredOrigin.z
        )
    }
}

// MARK: - Previews

#Preview("zero", traits: .fixedLayout(width: 400, height: 240)) {
    PreviewCanvas(width: 400, height: 240, background: .canvas) {
        OriginGizmo(authoredOrigin: .zero)
    }
}

#Preview("offset", traits: .fixedLayout(width: 400, height: 240)) {
    PreviewCanvas(width: 400, height: 240, background: .canvas) {
        OriginGizmo(authoredOrigin: Vector3(x: 0.42, y: -0.18, z: 1.05))
    }
}
