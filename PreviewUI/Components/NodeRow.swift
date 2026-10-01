import DesignSystem
import SwiftUI

/// One outliner row: type icon, name, and a visibility eye that fades in on hover.
///
/// Built for a native `List(selection:)` — the row draws **no** selection of its own. Hidden
/// nodes use `.tertiary` (`isMuted`), not opacity. Pass `paintsSelection: true` only for the
/// S1f custom-row fallback (accent wash + `.onMoveCommand` on the list).
public struct NodeRow<Selection: SelectionModel>: View {
    public var item: OutlinerItem
    public var isSelected: Bool
    public var selection: Selection
    /// When true, paint `DS.Color.selectionFill` — native `List` selection must leave this false.
    public var paintsSelection: Bool = false
    public var treeFolding: Bool = false
    public var isExpanded: Bool = false
    public var onToggleExpand: ((_ recursive: Bool) -> Void)? = nil

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        selection.isVisible(item.id)
    }

    /// Group / folder nodes with children use the chevron as the affordance — no dotted icon.
    private var showsNodeIcon: Bool {
        !(item.id.kind == .empty && item.hasChildren)
    }

    private var role: DSTypeRole {
        DSTypeRole(rawValue: item.id.kind.rawValue) ?? .empty
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            if treeFolding {
                treeGutter
            }

            DSListRow(
                item.name,
                isSelected: paintsSelection && isSelected,
                isMuted: !isVisible,
                icon: { iconSlot },
                accessory: {
                    if selection.canHideNodes {
                        eyeButton
                    }
                }
            )
            .accessibilityLabel("\(item.name), \(item.id.kind.displayTitle)")
            .accessibilityValue(isVisible ? "Visible" : "Hidden")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
        .accessibilityElement(children: .contain)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var iconSlot: some View {
        if showsNodeIcon {
            DSTypeIcon(role, isSelected: paintsSelection && isSelected)
        } else {
            Color.clear
                .frame(width: DS.Metrics.typeIcon, height: DS.Metrics.typeIcon)
                .accessibilityHidden(true)
        }
    }

    /// Depth indent + disclosure column — only the custom-row fallback uses this. Native
    /// `DisclosureGroup` in `OutlinerList` owns the chevron and indent.
    private var treeGutter: some View {
        HStack(spacing: OutlinerTreeMetrics.disclosureGap) {
            Color.clear
                .frame(width: CGFloat(item.depth) * OutlinerTreeMetrics.indentPerLevel)
                .accessibilityHidden(true)
            disclosure
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        let size = OutlinerTreeMetrics.disclosureSize
        if item.hasChildren {
            Button {
                onToggleExpand?(OutlinerOptionKey.isDown)
            } label: {
                Image(systemName: "chevron.down")
                    .font(DS.Font.micro.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: size, height: size)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .animation(DS.Motion.hoverFade(reduceMotion: reduceMotion), value: isExpanded)
            .help("Click to expand or collapse. Option-click to expand or collapse all nested nodes.")
            .accessibilityLabel(isExpanded ? "Collapse \(item.name)" : "Expand \(item.name)")
            .accessibilityHint("Option-click to expand or collapse the whole subtree")
        } else {
            Color.clear
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// Visibility toggle — click hides/shows; Option-click isolates (DESIGN.md).
    private var eyeButton: some View {
        Button {
            if OutlinerOptionKey.isDown {
                selection.isolate(selection.isolated == item.id ? nil : item.id)
            } else {
                selection.setVisible(item.id, !isVisible)
            }
        } label: {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(DS.Font.caption)
                .foregroundStyle(isVisible ? DS.Color.textSecondary : DS.Color.textTertiary)
                .frame(
                    width: OutlinerTreeMetrics.eyeSize,
                    height: OutlinerTreeMetrics.eyeSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .opacity(eyeOpacity)
        .animation(DS.Motion.hoverFade(reduceMotion: reduceMotion), value: isHovering)
        .animation(DS.Motion.hoverFade(reduceMotion: reduceMotion), value: isVisible)
        .help(isVisible ? "Hide" : "Show")
        .accessibilityLabel(isVisible ? "Hide \(item.name)" : "Show \(item.name)")
        .accessibilityHint("Option-click to isolate")
    }

    /// Resting sidebar is names only. Always show the eye when hidden so it can be found
    /// without hunting for hover.
    private var eyeOpacity: Double {
        if !isVisible { return isSelected ? 0.7 : 0.55 }
        if isHovering { return isSelected ? 0.55 : 0.28 }
        return 0
    }
}

// MARK: - Previews

private enum NodeRowPreviewFixtures {
    static let meshID = NodeID(kind: .mesh, index: 0)
    static let materialID = NodeID(kind: .material, index: 0)

    static let flatItem = OutlinerItem(id: materialID, name: "DefaultMaterial")
    static let meshItem = OutlinerItem(id: meshID, name: "Cube")

    static let treeParent = OutlinerItem(
        id: NodeID(kind: .empty, index: 0),
        name: "Scene",
        depth: 0,
        children: [meshItem]
    )
}

private struct NodeRowPreviewHost: View {
    enum Mode {
        case flat
        case tree
        case selected
        case hidden
    }

    var mode: Mode
    @State private var selection: MockSelectionModel

    init(mode: Mode) {
        self.mode = mode
        let meshID = NodeRowPreviewFixtures.meshID
        let materialID = NodeRowPreviewFixtures.materialID
        switch mode {
        case .flat, .tree:
            _selection = State(initialValue: MockSelectionModel(selected: nil))
        case .selected:
            _selection = State(initialValue: MockSelectionModel(selected: meshID))
        case .hidden:
            _selection = State(
                initialValue: MockSelectionModel(
                    selected: nil,
                    visibility: [materialID: false]
                )
            )
        }
    }

    var body: some View {
        PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 44) {
            switch mode {
            case .flat:
                NodeRow(
                    item: NodeRowPreviewFixtures.flatItem,
                    isSelected: false,
                    selection: selection
                )
            case .tree:
                NodeRow(
                    item: NodeRowPreviewFixtures.treeParent,
                    isSelected: false,
                    selection: selection,
                    treeFolding: true,
                    isExpanded: true,
                    onToggleExpand: { _ in }
                )
            case .selected:
                NodeRow(
                    item: NodeRowPreviewFixtures.meshItem,
                    isSelected: true,
                    selection: selection,
                    paintsSelection: true
                )
            case .hidden:
                NodeRow(
                    item: NodeRowPreviewFixtures.flatItem,
                    isSelected: false,
                    selection: selection
                )
            }
        }
    }
}

#Preview("flat", traits: .fixedLayout(width: 248, height: 44)) {
    NodeRowPreviewHost(mode: .flat)
}

#Preview("tree", traits: .fixedLayout(width: 248, height: 44)) {
    NodeRowPreviewHost(mode: .tree)
}

#Preview("selected", traits: .fixedLayout(width: 248, height: 44)) {
    NodeRowPreviewHost(mode: .selected)
}

#Preview("hidden", traits: .fixedLayout(width: 248, height: 44)) {
    NodeRowPreviewHost(mode: .hidden)
}
