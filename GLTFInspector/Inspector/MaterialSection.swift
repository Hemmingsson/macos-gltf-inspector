import AppKit
import GLTFCore
import simd
import SwiftUI

/// A material as the file authors it. Each fact is said once: the inspector header already
/// names a selected material, and present maps appear as chips (compact) or as sized rows
/// (full), never both.
struct MaterialSection: View {
    enum Density {
        /// A mesh is selected: its material's name and map chips.
        case compact
        /// The material itself is selected: its facts and sized maps.
        case full
    }

    var document: GLTFDocument
    var index: Int
    var density: Density

    private var material: GLTFDocument.Material { document.materials[index] }
    private var name: String { document.displayName(of: NodeID(kind: .material, index: index)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader("Material")
            Group {
                switch density {
                case .compact: compactBody
                case .full: fullBody
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.m) {
                DSTypeIcon(.material)
                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if !material.textures.isEmpty {
                FlexibleChipRow(items: material.textures.map(\.kind.shortTitle))
            }
        }
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            VStack(spacing: 0) {
                DSFactRow("Workflow", value: material.workflowTitle)
                DSFactRow("Alpha", value: material.alphaTitle)
                DSFactRow("Faces", value: material.isDoubleSided ? "Double-sided" : "Single-sided")
            }

            VStack(spacing: DS.Spacing.xs) {
                if let factor = material.visibleBaseColorFactor {
                    colorRow("Base color", SIMD3(factor.x, factor.y, factor.z))
                }
                if let value = material.visibleMetallicFactor {
                    DSFactorRow("Metallic", value: Double(value))
                }
                if let value = material.visibleRoughnessFactor {
                    DSFactorRow("Roughness", value: Double(value))
                }
                if let factor = material.visibleEmissiveFactor {
                    colorRow("Emissive", factor)
                }
                if let value = material.visibleEmissiveStrength {
                    DSFactRow("Emissive strength", value: String(format: "%.2g", value))
                }
                if let value = material.visibleNormalScale {
                    DSFactRow("Normal scale", value: String(format: "%.2g", value))
                }
                if let value = material.visibleOcclusionStrength {
                    DSFactorRow("Occlusion", value: Double(value))
                }
            }

            if !material.textures.isEmpty {
                VStack(spacing: 0) {
                    ForEach(material.textures, id: \.kind) { mapRow($0) }
                }
            }

            if let usage {
                DSFactRow("Used by", value: usage)
            }
        }
    }

    private var usage: String? {
        let names = document.meshNames(usingMaterial: index)
        guard !names.isEmpty else { return nil }
        return names.count <= 3 ? names.joined(separator: ", ") : "\(names.count) meshes"
    }

    private func mapRow(_ texture: GLTFDocument.TextureSlot) -> some View {
        HStack(spacing: DS.Spacing.m) {
            mapThumb(texture)
            Text(texture.kind.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.m)
            if let width = texture.width, let height = texture.height {
                Text("\(width)×\(height)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.primary)
            }
            if texture.texCoord != 0 {
                Text("UV\(texture.texCoord)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    @ViewBuilder
    private func mapThumb(_ texture: GLTFDocument.TextureSlot) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        Group {
            if let data = texture.thumbnailPNG, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .clipShape(shape)
            } else {
                shape.fill(.quinary)
            }
        }
        .frame(width: 28, height: 28)
        .overlay { shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline) }
        .accessibilityHidden(true)
    }

    private func colorRow(_ label: String, _ color: SIMD3<Float>) -> some View {
        let clamped = simd_clamp(color, .zero, .one)
        return DSFactRow(label) {
            HStack(spacing: DS.Spacing.s) {
                MaterialSwatch(color: Color(.sRGB, red: Double(clamped.x), green: Double(clamped.y), blue: Double(clamped.z)), size: 12)
                Text(String(format: "#%02X%02X%02X", Int((clamped.x * 255).rounded()),
                            Int((clamped.y * 255).rounded()), Int((clamped.z * 255).rounded())))
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Material \(name)"]
        if !material.textures.isEmpty {
            parts.append("maps: \(material.textures.map(\.kind.title).joined(separator: ", "))")
        }
        if density == .full {
            parts += [material.workflowTitle, material.alphaTitle]
            if let usage { parts.append("used by \(usage)") }
        }
        return parts.joined(separator: ", ")
    }
}
