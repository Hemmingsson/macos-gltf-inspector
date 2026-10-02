import DesignSystem
import SwiftUI

/// Bottom-leading corner axes — a fixed isometric triad giving a camera-orientation cue.
/// Not glass: the wireframe paints bare strokes over the canvas.
struct OrientationGizmo: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let origin = Self.origin(in: size)
                OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x + 30, y: origin.y), color: DS.Color.Axis.x)
                OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x, y: origin.y - 30), color: DS.Color.Axis.y)
                OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x + 18, y: origin.y + 10), color: DS.Color.Axis.z)

                OverlayMetrics.drawAxisLabel(context, "X", at: CGPoint(x: origin.x + 33, y: origin.y + 3), color: DS.Color.Axis.x)
                OverlayMetrics.drawAxisLabel(context, "Y", at: CGPoint(x: origin.x - 4, y: origin.y - 32), color: DS.Color.Axis.y)
                OverlayMetrics.drawAxisLabel(context, "Z", at: CGPoint(x: origin.x + 20, y: origin.y + 15), color: DS.Color.Axis.z)
            }

            GeometryReader { geo in
                Circle()
                    .fill(DS.Color.textTertiary)
                    .frame(width: 4.8, height: 4.8)
                    .position(Self.origin(in: geo.size))
            }
        }
        .frame(width: OverlayMetrics.orientationSize, height: OverlayMetrics.orientationSize)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orientation gizmo")
    }

    private static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * 0.30, y: size.height * 0.70)
    }
}

// MARK: - Previews

#Preview("default", traits: .fixedLayout(width: 120, height: 120)) {
    PreviewCanvas(width: 120, height: 120, background: .canvas) {
        OrientationGizmo()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(OverlayMetrics.inset)
    }
}
