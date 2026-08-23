import SwiftUI

/// The glTF-type vocabulary: one monochrome SF Symbol and one low-saturation tint per kind.
///
/// DESIGN.md — *colour is meaning, not decoration*. A reader learns five hues once (camera blue ·
/// light amber · material purple · animation green · mesh graphite) and can then scan the outliner
/// without reading a single label. That only works while the mapping is total and lives in exactly
/// one place, so every icon in the app comes from here rather than from a literal at the call site.
public struct NodeIcon: View {
    public var kind: NodeKind
    /// A selected row recolours icon *and* label to the selection blue, so the type tint yields
    /// to the selection instead of fighting it for the same 16 pt.
    public var isSelected: Bool = false

    public var body: some View {
        Image(systemName: Self.symbol(for: kind))
            .font(.system(size: 13))
            .foregroundStyle(isSelected ? Theme.selectionText : Self.tint(for: kind))
            // Fixed box so labels line up down the column whatever each glyph's natural width is.
            .frame(
                width: OutlinerTreeMetrics.iconSize,
                height: OutlinerTreeMetrics.iconSize
            )
            // The row already announces the kind in its accessibility label; the glyph is a
            // duplicate for VoiceOver.
            .accessibilityHidden(true)
    }

    /// SF Symbols only — no bundled art, so weight and appearance track the system font.
    public static func symbol(for kind: NodeKind) -> String {
        switch kind {
        case .scene: "square.stack.3d.up"
        case .mesh: "cube"
        case .camera: "video"
        case .light: "sun.max"
        case .material: "circle.lefthalf.filled"
        case .animation: "waveform.path"
        case .skin: "point.3.connected.trianglepath.dotted"
        case .morph: "slider.horizontal.3"
        case .empty: "circle.dotted"
        }
    }

    /// Only the five types the wireframe gives a hue get one. Structural kinds (skin, morph,
    /// transform-only empties) stay graphite: they are scaffolding, not content.
    public static func tint(for kind: NodeKind) -> Color {
        switch kind {
        case .camera: Theme.camera
        case .light: Theme.light
        case .material: Theme.material
        case .animation: Theme.animation
        case .scene, .mesh, .skin, .morph, .empty: Theme.mesh
        }
    }
}

// MARK: - Previews

#Preview("all kinds", traits: .fixedLayout(width: Theme.sidebarWidth, height: 320)) {
    PreviewCanvas(height: 320) {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(NodeKind.allCases, id: \.self) { kind in
                HStack(spacing: 8) {
                    NodeIcon(kind: kind)
                    Text(kind.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

#Preview("all kinds selected", traits: .fixedLayout(width: Theme.sidebarWidth, height: 320)) {
    PreviewCanvas(height: 320) {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(NodeKind.allCases, id: \.self) { kind in
                HStack(spacing: 8) {
                    NodeIcon(kind: kind, isSelected: true)
                    Text(kind.rawValue)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.selectionText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.vertical, 12)
    }
}
