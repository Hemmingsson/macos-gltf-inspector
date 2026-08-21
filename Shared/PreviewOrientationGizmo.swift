import RealityKit
import simd
import SwiftUI

/// Corner XYZ triad that tracks the preview camera orientation.
/// Separate from the world-origin gizmo parented under the turntable when Center is off.
struct PreviewOrientationGizmo: View {
    var interaction: PreviewInteraction

    private static let size: CGFloat = 66
    private static let axisLength: CGFloat = 26
    /// Matches Main.dc.html bottom-left SVG origin (room for axis labels).
    private static let origin = CGPoint(x: 20, y: 46)

    private static let xColor = Color(red: 0.886, green: 0.337, blue: 0.290) // #e2564a
    private static let yColor = Color(red: 0.204, green: 0.780, blue: 0.349) // #34c759
    private static let zColor = Color(red: 0.039, green: 0.518, blue: 1.0) // #0a84ff
    private static let hubColor = Color(red: 0.541, green: 0.541, blue: 0.557) // #8a8a8e

    var body: some View {
        // Poll the live camera entity — orbit mutates transforms without @Observable writes.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let _ = context.date
            Canvas { canvas, _ in
                draw(into: &canvas)
            }
            .frame(width: Self.size, height: Self.size)
        }
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(into context: inout GraphicsContext) {
        let rot = interaction.camera?.orientation(relativeTo: nil)
            ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        let axes = Self.projectedAxes(
            cameraOrientation: rot,
            origin: Self.origin,
            length: Self.axisLength
        )
        for axis in axes {
            var path = Path()
            path.move(to: Self.origin)
            path.addLine(to: axis.tip)
            context.stroke(path, with: .color(axis.color), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            let label = Text(axis.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(axis.color)
            context.draw(label, at: axis.labelPoint, anchor: .center)
        }

        let hub = CGRect(
            x: Self.origin.x - 2.4,
            y: Self.origin.y - 2.4,
            width: 4.8,
            height: 4.8
        )
        context.fill(Path(ellipseIn: hub), with: .color(Self.hubColor))
    }

    /// World axes expressed in camera space, projected to 2D (Y flipped for screen).
    /// Sorted far→near so nearer tips paint on top.
    static func projectedAxes(
        cameraOrientation: simd_quatf,
        origin: CGPoint,
        length: CGFloat
    ) -> [ProjectedAxis] {
        let inv = cameraOrientation.inverse
        let specs: [(String, SIMD3<Float>, Color)] = [
            ("X", SIMD3(1, 0, 0), xColor),
            ("Y", SIMD3(0, 1, 0), yColor),
            ("Z", SIMD3(0, 0, 1), zColor),
        ]
        let scale = Float(length)
        var result: [ProjectedAxis] = specs.map { label, world, color in
            let cam = inv.act(world)
            let tip = CGPoint(
                x: origin.x + CGFloat(cam.x * scale),
                y: origin.y - CGFloat(cam.y * scale)
            )
            // Nudge label past the tip along the screen direction from the hub.
            let dx = tip.x - origin.x
            let dy = tip.y - origin.y
            let mag = max(hypot(dx, dy), 1)
            let labelPoint = CGPoint(
                x: tip.x + dx / mag * 8,
                y: tip.y + dy / mag * 8
            )
            return ProjectedAxis(
                label: label,
                color: color,
                tip: tip,
                labelPoint: labelPoint,
                depth: cam.z
            )
        }
        // Camera looks down −Z; larger cam.z is closer to the viewer.
        result.sort { $0.depth < $1.depth }
        return result
    }

    struct ProjectedAxis {
        let label: String
        let color: Color
        let tip: CGPoint
        let labelPoint: CGPoint
        let depth: Float
    }
}
