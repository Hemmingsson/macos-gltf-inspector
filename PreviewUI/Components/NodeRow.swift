import AppKit
import SwiftUI

/// One selectable outliner row: tinted type icon, name, and a visibility eye that fades in on
/// hover.
///
/// Scene-graph sections pass `treeFolding: true` for disclosure chevrons and per-depth indent.
/// Flat sections (Materials, Animations, …) omit the tree gutter and stay leaf lists.
public struct NodeRow<Selection: SelectionModel>: View {
    public var item: OutlinerItem
    public var isSelected: Bool
    public var selection: Selection
    public var treeFolding: Bool = false
    public var isExpanded: Bool = false
    public var onToggleExpand: ((_ recursive: Bool) -> Void)? = nil
    public var select: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        selection.isVisible(item.id)
    }

    private var label: Color {
        isSelected ? Theme.selectionText : Theme.text
    }

    /// Group / folder nodes with children use the chevron as the affordance — no dotted icon.
    private var showsNodeIcon: Bool {
        !(item.id.kind == .empty && item.hasChildren)
    }

    public var body: some View {
        HStack(spacing: OutlinerTreeMetrics.contentGap) {
            if treeFolding {
                treeGutter
            }

            // Row select is its own button so the eye (and chevron) can be sibling controls
            // (SwiftUI nested-Button is unreliable). Shared padding/background keep one hit band.
            Button(action: select) {
                HStack(spacing: OutlinerTreeMetrics.contentGap) {
                    iconSlot
                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundStyle(label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(isVisible ? 1 : 0.45)
                    Spacer(minLength: OutlinerTreeMetrics.contentGap)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), \(item.id.kind.rawValue)")
            .accessibilityValue(isVisible ? "Visible" : "Hidden")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            eyeButton
        }
        .padding(.leading, treeFolding ? OutlinerTreeMetrics.treeLeading : OutlinerTreeMetrics.flatLeading)
        .padding(.trailing, OutlinerTreeMetrics.trailing)
        .padding(.vertical, OutlinerTreeMetrics.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        // `.row { margin: 0 6px }` — the selection fill stops short of the column edges
        // instead of running into the hairline.
        .padding(.horizontal, OutlinerTreeMetrics.rowMargin)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }

    /// Depth indent + disclosure column. Kept outside the select button so expand does not select.
    private var treeGutter: some View {
        HStack(spacing: OutlinerTreeMetrics.disclosureGap) {
            Color.clear
                .frame(width: CGFloat(item.depth) * OutlinerTreeMetrics.indentPerLevel)
                .accessibilityHidden(true)
            disclosure
        }
    }

    @ViewBuilder
    private var iconSlot: some View {
        if showsNodeIcon {
            NodeIcon(kind: item.id.kind, isSelected: isSelected)
        } else {
            Color.clear
                .frame(
                    width: OutlinerTreeMetrics.iconSize,
                    height: OutlinerTreeMetrics.iconSize
                )
                .accessibilityHidden(true)
        }
    }

    /// Chevron for parents; a fixed slot for leaves so labels stay column-aligned.
    @ViewBuilder
    private var disclosure: some View {
        let size = OutlinerTreeMetrics.disclosureSize
        if item.hasChildren {
            Button {
                onToggleExpand?(Self.isOptionDown)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .foregroundStyle(Theme.text3)
                    .frame(width: size, height: size)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .animation(
                Animation.previewChrome(reduceMotion, duration: 0.12),
                value: isExpanded
            )
            .help("Click to expand or collapse. Option-click to expand or collapse all nested nodes.")
            .accessibilityLabel(isExpanded ? "Collapse \(item.name)" : "Expand \(item.name)")
            .accessibilityHint("Option-click to expand or collapse the whole subtree")
        } else {
            Color.clear
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7).fill(Theme.selection)
        }
    }

    /// Visibility toggle — click hides/shows; Option-click isolates (DESIGN.md).
    private var eyeButton: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                selection.isolate(selection.isolated == item.id ? nil : item.id)
            } else {
                selection.setVisible(item.id, !isVisible)
            }
        } label: {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .font(.system(size: 12))
                .foregroundStyle(label)
                .frame(
                    width: OutlinerTreeMetrics.eyeSize,
                    height: OutlinerTreeMetrics.eyeSize
                )
                .contentShape(.rect)
        }
        .buttonStyle(EyeButtonStyle())
        // `.eye { opacity: 0.28 }`, `.row.sel .eye { opacity: 0.55 }` — and 0 until hover, so
        // a resting sidebar is names and nothing else. Always show when hidden so the user can
        // find the control again without hunting for hover.
        .opacity(eyeOpacity)
        .animation(Animation.previewChrome(reduceMotion, duration: 0.12), value: isHovering)
        .animation(Animation.previewChrome(reduceMotion, duration: 0.12), value: isVisible)
        .help(isVisible ? "Hide" : "Show")
        .accessibilityLabel(isVisible ? "Hide \(item.name)" : "Show \(item.name)")
        .accessibilityHint("Option-click to isolate")
    }

    private var eyeOpacity: Double {
        if !isVisible { return isSelected ? 0.7 : 0.55 }
        if isHovering { return isSelected ? 0.55 : 0.28 }
        return 0
    }

    private static var isOptionDown: Bool {
        let eventFlags = NSApp.currentEvent?.modifierFlags ?? []
        return eventFlags.contains(.option) || NSEvent.modifierFlags.contains(.option)
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
        case .flat:
            _selection = State(initialValue: MockSelectionModel(selected: nil))
        case .tree:
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
        PreviewCanvas(height: 44) {
            switch mode {
            case .flat:
                NodeRow(
                    item: NodeRowPreviewFixtures.flatItem,
                    isSelected: false,
                    selection: selection,
                    treeFolding: false
                ) {
                    selection.select(NodeRowPreviewFixtures.materialID)
                }
            case .tree:
                NodeRow(
                    item: NodeRowPreviewFixtures.treeParent,
                    isSelected: false,
                    selection: selection,
                    treeFolding: true,
                    isExpanded: true,
                    onToggleExpand: { _ in }
                ) {
                    selection.select(NodeRowPreviewFixtures.treeParent.id)
                }
            case .selected:
                NodeRow(
                    item: NodeRowPreviewFixtures.meshItem,
                    isSelected: true,
                    selection: selection,
                    treeFolding: false
                ) {
                    selection.select(nil)
                }
            case .hidden:
                NodeRow(
                    item: NodeRowPreviewFixtures.flatItem,
                    isSelected: false,
                    selection: selection,
                    treeFolding: false
                ) {
                    selection.select(NodeRowPreviewFixtures.materialID)
                }
            }
        }
    }
}

#Preview("flat", traits: .fixedLayout(width: Theme.sidebarWidth, height: 44)) {
    NodeRowPreviewHost(mode: .flat)
}

#Preview("tree", traits: .fixedLayout(width: Theme.sidebarWidth, height: 44)) {
    NodeRowPreviewHost(mode: .tree)
}

#Preview("selected", traits: .fixedLayout(width: Theme.sidebarWidth, height: 44)) {
    NodeRowPreviewHost(mode: .selected)
}

#Preview("hidden", traits: .fixedLayout(width: Theme.sidebarWidth, height: 44)) {
    NodeRowPreviewHost(mode: .hidden)
}
