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

// MARK: - Previews

#Preview("default") {
    PreviewCanvas(width: Theme.inspectorWidth) {
        InspectorSectionHeader(title: "Geometry")
    }
}
