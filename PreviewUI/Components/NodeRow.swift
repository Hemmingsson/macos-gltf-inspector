import DesignSystem
import SwiftUI

/// One outliner row: type icon, name, and a visibility eye that fades in on hover.
///
/// Built for a native `List(selection:)` — the row draws **no** selection of its own. Hidden
/// nodes use `.tertiary` (`isMuted`), not opacity.
public struct NodeRow<Selection: SelectionModel>: View {
    public var item: OutlinerItem
    public var isSelected: Bool
    public var selection: Selection

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
            DSListRow(
                item.name,
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
            DSTypeIcon(role)
        } else {
            Color.clear
                .frame(width: DS.Metrics.typeIcon, height: DS.Metrics.typeIcon)
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
    static let materialID = NodeID(kind: .material, index: 0)

    static let flatItem = OutlinerItem(id: materialID, name: "DefaultMaterial")
}

private struct NodeRowPreviewHost: View {
    enum Mode {
        case flat
        case hidden
    }

    var mode: Mode
    @State private var selection: MockSelectionModel

    init(mode: Mode) {
        self.mode = mode
        let materialID = NodeRowPreviewFixtures.materialID
        switch mode {
        case .flat:
            _selection = State(initialValue: MockSelectionModel(selected: nil))
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

#Preview("hidden", traits: .fixedLayout(width: 248, height: 44)) {
    NodeRowPreviewHost(mode: .hidden)
}
