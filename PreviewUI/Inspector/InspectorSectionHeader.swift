import SwiftUI

/// Quiet uppercase section label.
public struct InspectorSectionHeader: View {
    public var title: String

    public var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.text3)
            .padding(.top, 14)
            .padding(.horizontal, 14)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Compact chip used for geometry facts and present material maps (`.chip`).
public struct InspectorChip: View {
    public var title: String

    public var body: some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(Color.dynamic(light: 0x5B5B60, dark: 0xB0B0B6))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.dynamic(light: 0xEDEEF1, dark: 0x2B2B2E))
            )
    }
}

/// Label · value row shared by File / Material / extras facts.
public struct InspectorFactRow: View {
    public var label: String
    public var value: String

    public var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textValue)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }
}

/// Left-to-right wrap of chips. `chipsPerRow` matches inspector width (geometry ≈3, maps ≈4).
public struct FlexibleChipRow: View {
    public var items: [String]
    public var chipsPerRow: Int = 4

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { title in
                        InspectorChip(title: title)
                    }
                }
            }
        }
    }

    private var rows: [[String]] {
        let step = max(chipsPerRow, 1)
        return stride(from: 0, to: items.count, by: step).map { start in
            Array(items[start..<min(start + step, items.count)])
        }
    }
}

/// Read-only TRS cell (`.field`). Not editable — this is a viewer, not an editor.
public struct InspectorField: View {
    public var text: String
    @Environment(\.previewBorder) private var border

    public var body: some View {
        Text(text)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.card)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(border, lineWidth: Theme.hairlineWidth)
            }
    }
}

public extension NodeKind {
    /// Subtitle under the selected name in the inspector header.
    var displayTitle: String {
        switch self {
        case .scene: "Scene"
        case .mesh: "Mesh"
        case .camera: "Camera"
        case .light: "Light"
        case .material: "Material"
        case .animation: "Animation"
        case .skin: "Skin"
        case .morph: "Morph"
        case .empty: "Group"
        }
    }
}
