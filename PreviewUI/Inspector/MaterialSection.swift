import AppKit
import DesignSystem
import SwiftUI

/// Bound material readout.
///
/// Wireframe-simple: **say each fact once**. The inspector header already owns the material’s
/// name/kind when a material is selected, so this section never repeats that. Present maps appear
/// as chips *or* (full density) as a sized list — never both, and never also as a colour strip.
public struct MaterialSection: View {
    public enum Density {
        /// Mesh selection — name + present-map chips (Main@2x).
        case compact
        /// Material selected — facts + sized maps; header already shows the name.
        case full
    }

    public var material: MaterialInfo
    public var density: Density = .full

    public var body: some View {
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

    // MARK: Compact (mesh)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            HStack(spacing: DS.Spacing.m) {
                DSTypeIcon(.material)
                Text(material.name)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
            }

            if !material.orderedMaps.isEmpty {
                FlexibleChipRow(items: material.orderedMaps.map(\.shortTitle))
            }
        }
    }

    // MARK: Full (material selected)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            VStack(spacing: 0) {
                DSFactRow("Workflow", value: MaterialInspectorSupport.workflowTitle(material.workflow))
                DSFactRow("Alpha", value: MaterialInspectorSupport.alphaTitle(material))
                DSFactRow(
                    "Faces",
                    value: material.isDoubleSided ? "Double-sided" : "Single-sided"
                )
            }

            VStack(spacing: 0) {
                if MaterialInspectorSupport.showsBaseColorFactor(material),
                   let factor = material.baseColorFactor {
                    factorColorRow("Base color", factor)
                }
                if MaterialInspectorSupport.showsMetallic(material),
                   let value = material.metallicFactor {
                    DSFactRow("Metallic", value: MaterialInspectorSupport.scalarLabel(value))
                }
                if MaterialInspectorSupport.showsRoughness(material),
                   let value = material.roughnessFactor {
                    DSFactRow("Roughness", value: MaterialInspectorSupport.scalarLabel(value))
                }
                if MaterialInspectorSupport.showsEmissive(material) {
                    emissiveRow
                }
                if MaterialInspectorSupport.showsEmissiveStrength(material),
                   let value = material.emissiveStrength {
                    DSFactRow("Emissive strength", value: MaterialInspectorSupport.scalarLabel(value))
                }
                if MaterialInspectorSupport.showsNormalScale(material),
                   let value = material.normalScale {
                    DSFactRow("Normal scale", value: MaterialInspectorSupport.scalarLabel(value))
                }
                if MaterialInspectorSupport.showsOcclusionStrength(material),
                   let value = material.occlusionStrength {
                    DSFactRow("Occlusion", value: MaterialInspectorSupport.scalarLabel(value))
                }
            }

            // One map representation: sized rows with optional thumb. No chips above them.
            if !material.orderedTextures.isEmpty {
                VStack(spacing: 0) {
                    ForEach(material.orderedTextures) { texture in
                        mapRow(texture)
                    }
                }
            } else if !material.orderedMaps.isEmpty {
                FlexibleChipRow(items: material.orderedMaps.map(\.shortTitle))
            }

            if let usage = MaterialInspectorSupport.usageTitle(material) {
                DSFactRow("Used by", value: usage)
            }
        }
    }

    private func mapRow(_ texture: MaterialTextureInfo) -> some View {
        HStack(spacing: DS.Spacing.m) {
            mapThumb(texture)
            Text(texture.map.title)
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: DS.Spacing.m)
            if let size = texture.sizeLabel {
                Text(size)
                    .font(DS.Font.value)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            if texture.texCoord != 0 {
                Text("UV\(texture.texCoord)")
                    .font(DS.Font.subheadline.monospacedDigit())
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        .padding(.vertical, DS.Spacing.xxs)
    }

    @ViewBuilder
    private func mapThumb(_ texture: MaterialTextureInfo) -> some View {
        let side: CGFloat = 28
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        if let data = texture.thumbnailPNG, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.medium)
                .frame(width: side, height: side)
                .clipShape(shape)
                .overlay {
                    shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
                }
                .accessibilityHidden(true)
        } else {
            shape
                .fill(DS.Color.cardFill)
                .frame(width: side, height: side)
                .overlay {
                    shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
                }
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var emissiveRow: some View {
        let factor = material.emissiveFactor ?? .black
        DSFactRow("Emissive") {
            HStack(spacing: DS.Spacing.s) {
                MaterialSwatch(color: Color(rgb: factor), size: 12)
                Text(emissiveValueLabel(factor))
            }
        }
    }

    private func emissiveValueLabel(_ factor: RGBColor) -> String {
        MaterialInspectorSupport.hexLabel(factor)
    }

    private func factorColorRow(_ label: String, _ color: RGBColor) -> some View {
        DSFactRow(label) {
            HStack(spacing: DS.Spacing.s) {
                MaterialSwatch(color: Color(rgb: color), size: 12)
                Text(MaterialInspectorSupport.hexLabel(color))
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = ["Material \(material.name)"]
        let maps = material.orderedMaps.map(\.title)
        if !maps.isEmpty {
            parts.append("maps: \(maps.joined(separator: ", "))")
        }
        if density == .full {
            parts.append(MaterialInspectorSupport.workflowTitle(material.workflow))
            parts.append(MaterialInspectorSupport.alphaTitle(material))
            if let usage = MaterialInspectorSupport.usageTitle(material) {
                parts.append("used by \(usage)")
            }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview("compact") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        MaterialSection(material: MaterialFixtures.cube, density: .compact)
    }
}

#Preview("full") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        let detail = NodeDetailFixtures.material
        MaterialSection(material: detail.material!, density: .full)
    }
}
