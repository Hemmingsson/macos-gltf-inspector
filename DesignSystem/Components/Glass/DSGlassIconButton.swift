import SwiftUI

/// An icon-only glass action (Fit, Play, Open in…).
///
/// - Standalone: a `DS.Metrics.glassControl` circle with one `DS.Glass.control` layer.
/// - In an island (`DSGlassPlacement.inIsland`): no glass of its own.
///
/// `isEngaged` is for an action whose *result* is currently in effect (e.g. a camera preset is
/// active): the glass takes the subtle accent tint and the glyph turns `.tint`. It is a visual
/// hint only; state that VoiceOver should announce belongs in `.accessibilityValue` at the call
/// site, and an on/off feature is a `DSGlassToggleButton`, not an engaged button.
///
/// Rendered with `.buttonStyle(.plain)` so DS ink and the full circular hit / focus shape win over
/// `.borderless` styling; the system focus ring follows that shape.
public struct DSGlassIconButton: View {
    private let title: String
    private let systemImage: String
    private let isEngaged: Bool
    private let shortcut: KeyboardShortcut?
    private let action: () -> Void

    /// - Parameters:
    ///   - title: Action name ("Frame Model"): tooltip and accessibility label.
    ///   - systemImage: SF Symbol name.
    ///   - isEngaged: Tints the control while the action's result is in effect.
    ///   - shortcut: Optional keyboard shortcut from `DS.Shortcuts`.
    ///   - action: Runs on click.
    public init(
        _ title: String,
        systemImage: String,
        isEngaged: Bool = false,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isEngaged = isEngaged
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .dsGlassControlLabel(.circle, isHighlighted: isEngaged)
        }
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isEngaged)
        .keyboardShortcut(shortcut)
        .help(title)
    }
}

// MARK: - Previews

#Preview("icon button states", traits: .sizeThatFitsLayout) {
    DSGlassPreviewBackdrops {
        HStack(spacing: DS.Metrics.clusterSpacing) {
            DSGlassIconButton("Frame Model", systemImage: "viewfinder", shortcut: DS.Shortcuts.action(.fit)) {}
            DSGlassIconButton("Camera preset active", systemImage: "cube", isEngaged: true) {}
            DSGlassIconButton("Disabled", systemImage: "square.and.arrow.up") {}
                .disabled(true)
            DSGlassIsland {
                DSGlassIconButton("Play", systemImage: "play.fill") {}
                DSGlassIconButton("Engaged", systemImage: "repeat", isEngaged: true) {}
            }
        }
    }
    .frame(width: 360)
}
