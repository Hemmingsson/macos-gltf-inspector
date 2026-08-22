import SwiftUI

/// Bottom-leading corner axes — a fixed isometric triad giving a camera-orientation cue.
/// Not glass: the wireframe paints bare strokes over the canvas.
struct OrientationGizmo: View {
    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: size.width * 0.30, y: size.height * 0.70)
            OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x + 30, y: origin.y), color: OverlayMetrics.axisX)
            OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x, y: origin.y - 30), color: OverlayMetrics.axisY)
            OverlayMetrics.strokeAxis(context, from: origin, to: CGPoint(x: origin.x + 18, y: origin.y + 10), color: OverlayMetrics.axisZ)

            var hub = Path()
            hub.addEllipse(in: CGRect(x: origin.x - 2.4, y: origin.y - 2.4, width: 4.8, height: 4.8))
            context.fill(hub, with: .color(Theme.text3))

            OverlayMetrics.drawAxisLabel(context, "X", at: CGPoint(x: origin.x + 33, y: origin.y + 3), color: OverlayMetrics.axisX)
            OverlayMetrics.drawAxisLabel(context, "Y", at: CGPoint(x: origin.x - 4, y: origin.y - 32), color: OverlayMetrics.axisY)
            OverlayMetrics.drawAxisLabel(context, "Z", at: CGPoint(x: origin.x + 20, y: origin.y + 15), color: OverlayMetrics.axisZ)
        }
        .frame(width: OverlayMetrics.orientationSize, height: OverlayMetrics.orientationSize)
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orientation gizmo")
    }
}
