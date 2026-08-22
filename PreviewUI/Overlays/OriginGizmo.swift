import SwiftUI

/// World-origin axes shown on the canvas when Center is off, or when the file has a non-zero
/// authored origin. Drawn as a triad at the canvas centre, with the authored origin on its tag.
struct OriginGizmo: View {
    /// Authored origin relative to the model, in metres — shown on the tag.
    var authoredOrigin: Vector3

    var body: some View {
        ZStack {
            Canvas { context, size in
                let origin = CGPoint(x: size.width * 0.5, y: size.height * 0.58)
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

                var hub = Path()
                hub.addEllipse(in: CGRect(x: origin.x - 3, y: origin.y - 3, width: 6, height: 6))
                context.fill(hub, with: .color(Theme.glyph))

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

            Text(tag)
                .font(.system(size: 11))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.card.opacity(0.85))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Theme.hair, lineWidth: Theme.hairlineWidth)
                }
                .offset(x: -100, y: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Origin gizmo")
        .accessibilityValue(tag)
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
