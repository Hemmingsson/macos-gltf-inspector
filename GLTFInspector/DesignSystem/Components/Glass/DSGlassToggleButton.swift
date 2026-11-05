import SwiftUI

/// An icon-only on/off glass control (Floor, the perspective / orthographic toggle).
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
struct DSGlassToggleButton: View {
    private let title: String
    private let systemImage: String
    private let assetImage: String?
    @Binding private var isOn: Bool
    private let shortcut: KeyboardShortcut?

    /// - Parameters:
    ///   - title: Fixed feature name ("Floor"): tooltip and accessibility label.
    ///   - systemImage: SF Symbol name, used when `assetImage` is nil.
    ///   - assetImage: Catalog image drawn instead of the symbol.
    ///   - isOn: The state.
    ///   - shortcut: Optional keyboard shortcut — pass the `Shortcuts` entry so the menu bar
    ///     and the control share one binding.
    init(
        _ title: String,
        systemImage: String = "circle",
        assetImage: String? = nil,
        isOn: Binding<Bool>,
        shortcut: KeyboardShortcut? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.assetImage = assetImage
        self._isOn = isOn
        self.shortcut = shortcut
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            icon
                .labelStyle(.iconOnly)
                .dsGlassControlLabel(.circle, isHighlighted: isOn)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isOn)
        .keyboardShortcut(shortcut)
        .help(title)
    }

    @ViewBuilder
    private var icon: some View {
        if let assetImage {
            Label {
                Text(title)
            } icon: {
                Image(assetImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}
