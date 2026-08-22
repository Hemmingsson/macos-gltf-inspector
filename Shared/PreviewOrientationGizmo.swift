import simd
import SwiftUI

/// Camera-space projection for a corner XYZ triad (math for tests / a future tracked gizmo).
/// The live host canvas draws the static `OrientationGizmo` in PreviewUI.
enum PreviewOrientationGizmo {
    private static let xColor = Color(red: 0.886, green: 0.337, blue: 0.290) // #e2564a
    private static let yColor = Color(red: 0.204, green: 0.780, blue: 0.349) // #34c759
    private static let zColor = Color(red: 0.039, green: 0.518, blue: 1.0) // #0a84ff

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
