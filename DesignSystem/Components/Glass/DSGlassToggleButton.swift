import SwiftUI

/// An icon-only on/off glass control (Floor, Auto-rotate, Center, Orthographic).
///
/// A real `Toggle` in `.button` style, so VoiceOver announces it as a toggle with its state
/// ("Floor, on") under a **fixed** label — the label names the feature, never the action the
/// next click performs. Shown icon-only; the title is the tooltip and accessibility label.
///
/// - Standalone: a `DS.Metrics.glassControl` circle with one `DS.Glass.control` layer; when on,
///   the glass takes a subtle accent tint (`DS.Glass.controlEngaged`) and the glyph turns `.tint`.
/// - In an island (`DSGlassPlacement.inIsland`): no glass; on-state is the `.tint` glyph.
///
/// Rendered with `.buttonStyle(.plain)`: the glass is the whole chrome. `.borderless` would
/// re-colour the glyph (secondary at rest, accent when on) and ignore DS ink. The system focus ring
/// follows the circular content shape.
public struct DSGlassToggleButton: View {
    private let title: String
    private let systemImage: String
    @Binding private var isOn: Bool
    private let shortcut: KeyboardShortcut?

    /// - Parameters:
    ///   - title: Fixed feature name ("Floor"): tooltip and accessibility label.
    ///   - systemImage: SF Symbol name.
    ///   - isOn: The state.
    ///   - shortcut: Optional keyboard shortcut — pass the `DS.Shortcuts` entry so the menu bar
    ///     and the control share one binding.
    public init(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        shortcut: KeyboardShortcut? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self._isOn = isOn
        self.shortcut = shortcut
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .dsGlassControlLabel(.circle, isHighlighted: isOn)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isOn)
        .keyboardShortcut(shortcut)
        .help(title)
    }
}

// MARK: - Previews

private struct DSGlassToggleButtonPreview: View {
    @State private var off = false
    @State private var on = true
    @State private var islandOff = false
    @State private var islandOn = true

    var body: some View {
        HStack(spacing: DS.Metrics.clusterSpacing) {
            DSGlassToggleButton("Orthographic", systemImage: "perspective", isOn: $off)
            DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $on)
            DSGlassToggleButton(
                "Auto-rotate",
                systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                isOn: $on,
                shortcut: DS.Shortcuts.action(.autoRotate)
            )
            DSGlassToggleButton("Unavailable", systemImage: "dot.scope", isOn: $off)
                .disabled(true)
            DSGlassIsland {
                DSGlassToggleButton("Grid", systemImage: "grid", isOn: $islandOff)
                DSGlassToggleButton("Floor", systemImage: "circle.grid.cross", isOn: $islandOn)
            }
        }
    }
}

#Preview("toggle states", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        DSGlassToggleButtonPreview()
    }
    .frame(width: 360)
}
