import DesignSystem
import SwiftUI

/// Kind-specific extras when the selection is not a mesh (camera / light / animation / skin / morph).
public struct NodeExtrasSection: View {
    public var detail: NodeDetail

    public var body: some View {
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
            DSSectionHeader("Camera")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
            VStack(spacing: 0) {
                DSFactRow("Projection", value: camera.projection.title)
                if let fov = camera.fieldOfViewDegrees {
                    DSFactRow("Field of view", value: String(format: "%.1f°", fov))
                }
                if let xMag = camera.xMag {
                    DSFactRow("X mag", value: String(format: "%.2f", xMag))
                }
                if let yMag = camera.yMag {
                    DSFactRow("Y mag", value: String(format: "%.2f", yMag))
                }
                DSFactRow("Near", value: String(format: "%.2f", camera.zNear))
                if let far = camera.zFar {
                    DSFactRow("Far", value: String(format: "%.1f", far))
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
    }

    private func lightBlock(_ light: LightInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Light")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
            VStack(spacing: 0) {
                DSFactRow("Kind", value: light.kind.rawValue.capitalized)
                DSFactRow("Intensity", value: light.intensity.formatted())
                if let range = light.range {
                    DSFactRow("Range", value: String(format: "%.1f", range))
                }
                if let inner = light.innerConeDegrees {
                    DSFactRow("Inner cone", value: String(format: "%.1f°", inner))
                }
                if let outer = light.outerConeDegrees {
                    DSFactRow("Outer cone", value: String(format: "%.1f°", outer))
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
    }

    private func animationBlock(_ animation: AnimationInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Animation")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
            VStack(spacing: 0) {
                DSFactRow("Duration", value: formatDuration(animation.duration))
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
    }

    private func skinBlock(_ skin: SkinInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Skin")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
            VStack(alignment: .leading, spacing: 0) {
                DSFactRow("Joints", value: "\(skin.jointCount)")
                if !skin.jointNames.isEmpty {
                    Text(skin.jointNames.joined(separator: ", "))
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.vertical, DS.Spacing.xs)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
        }
    }

    private func morphBlock(_ morph: MorphInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Morph")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)
            VStack(alignment: .leading, spacing: 0) {
                DSFactRow("Mesh", value: morph.meshName)
                DSFactRow("Targets", value: "\(morph.targetNames.count)")
                if !morph.targetNames.isEmpty {
                    Text(morph.targetNames.joined(separator: ", "))
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.vertical, DS.Spacing.xs)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.m)
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

// MARK: - Previews

#Preview("camera") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        NodeExtrasSection(detail: NodeDetailFixtures.camera)
    }
}

#Preview("light") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        NodeExtrasSection(detail: NodeDetailFixtures.light)
    }
}

#Preview("animation") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        NodeExtrasSection(detail: NodeDetailFixtures.animation)
    }
}

#Preview("skin") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        NodeExtrasSection(detail: NodeDetailFixtures.skin)
    }
}

#Preview("morph") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        NodeExtrasSection(detail: NodeDetailFixtures.morph)
    }
}
