import GLTFCore
import SwiftUI

// Read-only fact blocks for the inspector, one per glTF entry type.

struct CameraSection: View {
    var camera: GLTFDocument.Camera

    var body: some View {
        FactBlock("Camera") {
            DSFactRow("Projection", value: camera.type == "orthographic" ? "Orthographic" : "Perspective")
            if let yfov = camera.yfov {
                DSFactRow("Field of view", value: String(format: "%.1f°", yfov * 180 / .pi))
            }
            if let xmag = camera.xmag {
                DSFactRow("X mag", value: String(format: "%.2f", xmag))
            }
            if let ymag = camera.ymag {
                DSFactRow("Y mag", value: String(format: "%.2f", ymag))
            }
            DSFactRow("Near", value: String(format: "%.2f", camera.znear))
            if let zfar = camera.zfar {
                DSFactRow("Far", value: String(format: "%.1f", zfar))
            }
        }
    }
}

struct LightSection: View {
    var light: GLTFDocument.Light

    var body: some View {
        FactBlock("Light") {
            DSFactRow("Kind", value: light.type.capitalized)
            DSFactRow("Intensity", value: Double(light.intensity).formatted())
            if let range = light.range {
                DSFactRow("Range", value: String(format: "%.1f", range))
            }
            if let inner = light.innerCone {
                DSFactRow("Inner cone", value: String(format: "%.1f°", inner * 180 / .pi))
            }
            if let outer = light.outerCone {
                DSFactRow("Outer cone", value: String(format: "%.1f°", outer * 180 / .pi))
            }
        }
    }
}

struct AnimationSection: View {
    var animation: GLTFDocument.Animation

    var body: some View {
        FactBlock("Animation") {
            DSFactRow("Duration", value: animation.duration >= 60
                ? "\(Int(animation.duration) / 60)m \(Int(animation.duration) % 60)s"
                : String(format: "%.1fs", animation.duration))
        }
    }
}

struct SkinSection: View {
    var skin: GLTFDocument.Skin

    var body: some View {
        FactBlock("Skin") {
            DSFactRow("Joints", value: "\(skin.jointNames.count)")
            NameList(names: skin.jointNames)
        }
    }
}

struct MorphSection: View {
    var morph: GLTFDocument.Morph
    var meshName: String

    var body: some View {
        FactBlock("Morph") {
            DSFactRow("Mesh", value: meshName)
            DSFactRow("Targets", value: "\(morph.targetNames.count)")
            NameList(names: morph.targetNames)
        }
    }
}

/// A section header over fact rows, with the inspector's insets.
struct FactBlock<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.m)
        }
    }
}

private struct NameList: View {
    var names: [String]

    var body: some View {
        if !names.isEmpty {
            Text(names.joined(separator: ", "))
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.vertical, DS.Spacing.xs)
        }
    }
}
