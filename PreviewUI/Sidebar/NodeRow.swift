import AppKit
import SwiftUI

/// One selectable outliner row: tinted type icon, name, and a visibility eye that fades in on
/// hover (Main-html `.row` / `.row.sel` / `.row.child` / `.eye`).
///
/// When `treeFolding` is on (Meshes), a disclosure chevron + faint depth guides replace the
/// binary child indent. Flat sections leave `treeFolding` false so they stay leaf lists.
struct NodeRow<Selection: SelectionModel>: View {
    var item: OutlinerItem
    var isSelected: Bool
    var selection: Selection
    var treeFolding: Bool = false
    var isExpanded: Bool = false
    var onToggleExpand: ((_ recursive: Bool) -> Void)? = nil
    var select: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVisible: Bool {
        selection.isVisible(item.id)
    }

    private static var isOptionDown: Bool {
        let eventFlags = NSApp.currentEvent?.modifierFlags ?? []
        return eventFlags.contains(.option) || NSEvent.modifierFlags.contains(.option)
    }

    var body: some View {
        HStack(spacing: 8) {
            if treeFolding {
                HStack(spacing: OutlinerTreeMetrics.gap) {
                    leadingGutter
                    disclosure
                }
            }

            // Row select is its own button so the eye (and chevron) can be sibling controls
            // (SwiftUI nested-Button is unreliable). Shared padding/background keep one hit band.
            Button(action: select) {
                HStack(spacing: 8) {
                    NodeIcon(kind: item.id.kind, isSelected: isSelected)

                    Text(item.name)
                        .font(.system(size: 13))
                        .foregroundStyle(label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .opacity(isVisible ? 1 : 0.45)

                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name), \(item.id.kind.rawValue)")
            .accessibilityValue(isVisible ? "Visible" : "Hidden")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            eyeButton
        }
        .padding(.leading, treeFolding ? 8 : (item.depth > 0 ? 30 : 14))
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        // `.row { margin: 0 6px }` — the selection fill stops short of the column edges
        // instead of running into the hairline.
        .padding(.horizontal, 6)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }

    /// Ancestor indent + faint vertical guides through each parent arrow center.
    private var leadingGutter: some View {
        let step = OutlinerTreeMetrics.step
        let arrow = OutlinerTreeMetrics.arrow
        return ZStack(alignment: .leading) {
            Color.clear.frame(width: CGFloat(item.depth) * step)
            ForEach(0..<item.depth, id: \.self) { level in
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                    .padding(.leading, CGFloat(level) * step + arrow / 2 - 0.5)
            }
        }
        .accessibilityHidden(true)
    }

    /// Chevron for parents; clear 14×14 slot for leaves so labels stay column-aligned.
    /// Kept *outside* the select button so expand does not also select.
    @ViewBuilder
    private var disclosure: some View {
        Group {
            if item.hasChildren {
                Button {
                    onToggleExpand?(Self.isOptionDown)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(Theme.text3)
                        .frame(width: OutlinerTreeMetrics.arrow, height: OutlinerTreeMetrics.arrow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(
                    Animation.previewChrome(reduceMotion, duration: 0.12),
                    value: isExpanded
                )
                .help("Click to expand or collapse. Option-click to expand or collapse all nested meshes.")
                .accessibilityLabel(isExpanded ? "Collapse \(item.name)" : "Expand \(item.name)")
                .accessibilityHint("Option-click to expand or collapse the whole subtree")
            } else {
                Color.clear
                    .frame(width: OutlinerTreeMetrics.arrow, height: OutlinerTreeMetrics.arrow)
            }
        }
    }

    /// Selected rows swap the graphite label for the deeper selection blue (`.row.sel`), so the
    /// row reads as chosen even where the 12%-alpha fill is nearly invisible.
    private var label: Color {
        isSelected ? Theme.selectionText : Theme.text
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
                .frame(width: 18, height: 18)
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
}

private struct EyeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                PreviewFocusStroke(shape: .roundedRect(4))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
