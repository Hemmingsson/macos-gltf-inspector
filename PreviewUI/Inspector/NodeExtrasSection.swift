import SwiftUI

/// Kind-specific extras when the selection is not a mesh (camera / light / animation).
struct NodeExtrasSection: View {
    var detail: NodeDetail

    var body: some View {
        Group {
            if let camera = detail.camera {
                cameraBlock(camera)
            }
            if let light = detail.light {
                lightBlock(light)
            }
            if let animation = detail.animation {
                animationBlock(animation)
            }
        }
    }

    private func cameraBlock(_ camera: CameraInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Camera")
            VStack(spacing: 0) {
                InspectorFactRow(label: "Projection", value: camera.projection.title)
                if let fov = camera.fieldOfViewDegrees {
                    InspectorFactRow(label: "Field of view", value: String(format: "%.1f°", fov))
                }
                InspectorFactRow(label: "Near", value: String(format: "%.2f", camera.zNear))
                if let far = camera.zFar {
                    InspectorFactRow(label: "Far", value: String(format: "%.1f", far))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func lightBlock(_ light: LightInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Light")
            VStack(spacing: 0) {
                InspectorFactRow(label: "Kind", value: light.kind.rawValue.capitalized)
                InspectorFactRow(label: "Intensity", value: light.intensity.formatted())
                if let range = light.range {
                    InspectorFactRow(label: "Range", value: String(format: "%.1f", range))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func animationBlock(_ animation: AnimationInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Animation")
            VStack(spacing: 0) {
                InspectorFactRow(label: "Duration", value: formatDuration(animation.duration))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds >= 60 {
            let minutes = Int(seconds) / 60
            let rem = Int(seconds) % 60
            return "\(minutes)m \(rem)s"
        }
        return String(format: "%.1fs", seconds)
    }
}
