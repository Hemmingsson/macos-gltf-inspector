import DesignSystem
import SwiftUI

/// `DS.Glass` variants over the three backdrops.
struct GlassTokensPage: View {
    var body: some View {
        CatalogPageView(page: .glass) {
            StateGroup(title: "Variants", note: "Each capsule is one glass layer inside one GlassEffectContainer.") {
                StateRow("DS.Glass.control", note: "Glass.regular.interactive() — resting control") {
                    sample("control", systemImage: "circle.grid.cross", glass: DS.Glass.control)
                }
                StateRow("DS.Glass.controlEngaged", note: "accent @ 18 % tint — on / engaged control") {
                    sample("controlEngaged", systemImage: "circle.grid.cross", glass: DS.Glass.controlEngaged, isOn: true)
                }
                StateRow("DS.Glass.controlOn(tint:)", note: "full-strength tint — reference only, not used by components") {
                    sample("controlOn(accent)", systemImage: "circle.grid.cross", glass: DS.Glass.controlOn())
                }
                StateRow("DS.Glass.hud", note: "Glass.regular — non-interactive readout") {
                    sample("1.00 × 1.00 × 1.00 m", systemImage: "cube", glass: DS.Glass.hud)
                }
            }

            StateGroup(title: "Container spacing", note: "DS.Glass.containerSpacing = \(DS.Glass.containerSpacing.formatted()) pt: islands sample together, stay separate at rest.") {
                StateRow("Three islands") {
                    GlassEffectContainer(spacing: DS.Glass.containerSpacing) {
                        HStack(spacing: DS.Metrics.clusterSpacing) {
                            circle(DS.Glass.control)
                            circle(DS.Glass.controlEngaged)
                            circle(DS.Glass.control)
                        }
                    }
                }
            }
        }
    }

    private func sample(_ title: String, systemImage: String, glass: Glass, isOn: Bool = false) -> some View {
        GlassEffectContainer(spacing: DS.Glass.containerSpacing) {
            Label(title, systemImage: systemImage)
                .font(DS.Font.body)
                .foregroundStyle(isOn ? AnyShapeStyle(DS.Color.selectionText) : AnyShapeStyle(DS.Color.textPrimary))
                .padding(.horizontal, DS.Spacing.l)
                .frame(height: DS.Metrics.glassControl)
                .glassEffect(glass, in: .capsule)
        }
    }

    private func circle(_ glass: Glass) -> some View {
        Color.clear
            .frame(width: DS.Metrics.glassControl, height: DS.Metrics.glassControl)
            .glassEffect(glass, in: .circle)
    }
}

/// `DS.Motion` durations, live Reduce Motion state and a demo of the chrome curve.
struct MotionPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShifted = false
    @State private var isHovering = false

    var body: some View {
        CatalogPageView(page: .motion) {
            StateGroup(title: "Tokens") {
                VStack(spacing: DS.Spacing.s) {
                    DSFactRow("DS.Motion.chromeDuration", value: "\(DS.Motion.chromeDuration.formatted()) s · easeInOut")
                    DSFactRow("DS.Motion.hoverDuration", value: "\(DS.Motion.hoverDuration.formatted()) s · easeInOut")
                    DSFactRow("Reduce Motion (system)", value: reduceMotion ? "On — curves are nil" : "Off")
                }
                .frame(maxWidth: 520)
            }

            StateGroup(title: "Demo") {
                HStack(spacing: DS.Spacing.xl) {
                    DSButton("Move", size: .small) {
                        withAnimation(DS.Motion.chrome(reduceMotion: reduceMotion)) { isShifted.toggle() }
                    }
                    Capsule()
                        .fill(DS.Color.accent)
                        .frame(width: 48, height: 20)
                        .offset(x: isShifted ? 160 : 0)
                        .frame(width: 220, alignment: .leading)
                        .accessibilityHidden(true)
                }
                HStack(spacing: DS.Spacing.m) {
                    Text("Hover here")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                    Image(systemName: "eye")
                        .foregroundStyle(DS.Color.textPrimary)
                        .opacity(isHovering ? 1 : 0)
                        .animation(DS.Motion.hoverFade(reduceMotion: reduceMotion), value: isHovering)
                }
                .padding(DS.Spacing.m)
                .background(DS.Color.cardFill, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
                .onHover { isHovering = $0 }
            }
        }
    }
}

/// The `DS.Shortcuts` table, with a duplicate check.
struct ShortcutsPage: View {
    private var entries: [DS.Shortcuts.Entry] { DS.Shortcuts.all }

    private var duplicates: [String] {
        let keys = entries.map { Self.format($0.shortcut) }
        return Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.map(\.key).sorted()
    }

    var body: some View {
        CatalogPageView(page: .shortcuts) {
            StateGroup(title: "Table") {
                if duplicates.isEmpty {
                    DSStatusBadge("\(entries.count) shortcuts, no duplicates", status: .valid)
                        .frame(maxWidth: 520)
                } else {
                    DSStatusBadge("Duplicate: \(duplicates.joined(separator: ", "))", status: .error)
                        .frame(maxWidth: 520)
                }
                VStack(spacing: DS.Spacing.s) {
                    ForEach(entries) { entry in
                        DSFactRow(entry.id, value: Self.format(entry.shortcut))
                    }
                }
                .frame(maxWidth: 520)
            }
        }
    }

    static func format(_ shortcut: KeyboardShortcut) -> String {
        var text = ""
        if shortcut.modifiers.contains(.control) { text += "⌃" }
        if shortcut.modifiers.contains(.option) { text += "⌥" }
        if shortcut.modifiers.contains(.shift) { text += "⇧" }
        if shortcut.modifiers.contains(.command) { text += "⌘" }
        return text + String(shortcut.key.character).uppercased()
    }
}
