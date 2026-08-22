import SwiftUI

/// Bound material readout.
///
/// Wireframe-simple: **say each fact once**. The inspector header already owns the material’s
/// name/kind when a material is selected, so this section never repeats that. Present maps appear
/// as chips *or* (full density) as a sized list — never both, and never also as a colour strip.
struct MaterialSection: View {
    enum Density {
        /// Mesh selection — name + present-map chips (Main@2x).
        case compact
        /// Material selected — facts + sized maps; header already shows the name.
        case full
    }

    var material: MaterialInfo
    var density: Density = .full

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Material")

            Group {
                switch density {
                case .compact: compactBody
                case .full: fullBody
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Compact (mesh)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NodeIcon(kind: .material)
                Text(material.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }

            if !material.orderedMaps.isEmpty {
                FlexibleChipRow(items: material.orderedMaps.map(\.shortTitle), chipsPerRow: 4)
            }
        }
    }

    // MARK: Full (material selected)

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                InspectorFactRow(
                    label: "Workflow",
                    value: MaterialInspectorSupport.workflowTitle(material.workflow)
                )
                InspectorFactRow(
                    label: "Alpha",
                    value: MaterialInspectorSupport.alphaTitle(material)
                )
                InspectorFactRow(
                    label: "Faces",
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
                    InspectorFactRow(
                        label: "Metallic",
                        value: MaterialInspectorSupport.scalarLabel(value)
                    )
                }
                if MaterialInspectorSupport.showsRoughness(material),
                   let value = material.roughnessFactor {
                    InspectorFactRow(
                        label: "Roughness",
                        value: MaterialInspectorSupport.scalarLabel(value)
                    )
                }
                if MaterialInspectorSupport.showsEmissive(material) {
                    emissiveRow
                }
                if MaterialInspectorSupport.showsNormalScale(material),
                   let value = material.normalScale {
                    InspectorFactRow(
                        label: "Normal scale",
                        value: MaterialInspectorSupport.scalarLabel(value)
                    )
                }
                if MaterialInspectorSupport.showsOcclusionStrength(material),
                   let value = material.occlusionStrength {
                    InspectorFactRow(
                        label: "Occlusion",
                        value: MaterialInspectorSupport.scalarLabel(value)
                    )
                }
            }

            // One map representation: sized rows. No chips and no colour strip above them.
            if !material.orderedTextures.isEmpty {
                VStack(spacing: 0) {
                    ForEach(material.orderedTextures) { texture in
                        mapRow(texture)
                    }
                }
            } else if !material.orderedMaps.isEmpty {
                FlexibleChipRow(items: material.orderedMaps.map(\.shortTitle), chipsPerRow: 4)
            }

            if let usage = MaterialInspectorSupport.usageTitle(material) {
                InspectorFactRow(label: "Used by", value: usage)
            }
        }
    }

    private func mapRow(_ texture: MaterialTextureInfo) -> some View {
        HStack(spacing: 8) {
            Text(texture.map.title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let size = texture.sizeLabel {
                Text(size)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.textValue)
            }
            if texture.texCoord != 0 {
                Text("UV\(texture.texCoord)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.text3)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var emissiveRow: some View {
        let factor = material.emissiveFactor ?? .black
        HStack(spacing: 6) {
            Text("Emissive")
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            MaterialSwatch(color: Color(rgb: factor), size: 12)
            Text(emissiveValueLabel(factor))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textValue)
        }
        .padding(.vertical, 2)
    }

    private func emissiveValueLabel(_ factor: RGBColor) -> String {
        var parts = [MaterialInspectorSupport.hexLabel(factor)]
        if let strength = material.emissiveStrength, abs(strength - 1) > 0.004 {
            parts.append("×\(MaterialInspectorSupport.scalarLabel(strength))")
        }
        return parts.joined(separator: " ")
    }

    private func factorColorRow(_ label: String, _ color: RGBColor) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            MaterialSwatch(color: Color(rgb: color), size: 12)
            Text(MaterialInspectorSupport.hexLabel(color))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textValue)
        }
        .padding(.vertical, 2)
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

// MARK: - Local chrome

private struct MaterialSwatch: View {
    var color: Color
    var size: CGFloat
    @Environment(\.previewBorder) private var border

    var body: some View {
        RoundedRectangle(cornerRadius: max(4, size * 0.18), style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: max(4, size * 0.18), style: .continuous)
                    .strokeBorder(border, lineWidth: Theme.hairlineWidth)
            }
            .accessibilityHidden(true)
    }
}
