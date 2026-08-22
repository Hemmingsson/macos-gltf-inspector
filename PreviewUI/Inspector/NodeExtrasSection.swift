import SwiftUI

/// Kind-specific extras when the selection is not a mesh (camera / light / animation / skin / morph).
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
            if let skin = detail.skin {
                skinBlock(skin)
            }
            if let morph = detail.morph {
                morphBlock(morph)
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
                if let xMag = camera.xMag {
                    InspectorFactRow(label: "X mag", value: String(format: "%.2f", xMag))
                }
                if let yMag = camera.yMag {
                    InspectorFactRow(label: "Y mag", value: String(format: "%.2f", yMag))
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
                if let inner = light.innerConeDegrees {
                    InspectorFactRow(label: "Inner cone", value: String(format: "%.1f°", inner))
                }
                if let outer = light.outerConeDegrees {
                    InspectorFactRow(label: "Outer cone", value: String(format: "%.1f°", outer))
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

    private func skinBlock(_ skin: SkinInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Skin")
            VStack(alignment: .leading, spacing: 0) {
                InspectorFactRow(label: "Joints", value: "\(skin.jointCount)")
                if !skin.jointNames.isEmpty {
                    Text(skin.jointNames.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private func morphBlock(_ morph: MorphInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Morph")
            VStack(alignment: .leading, spacing: 0) {
                InspectorFactRow(label: "Mesh", value: morph.meshName)
                InspectorFactRow(label: "Targets", value: "\(morph.targetNames.count)")
                if !morph.targetNames.isEmpty {
                    Text(morph.targetNames.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .padding(.vertical, 4)
                }
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
