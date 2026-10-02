import DesignSystem
import SwiftUI

/// The view-mode chip and its menu: Shaded · Wireframe · every debug channel the file *has*.
///
/// **Full names, never abbreviations** (DESIGN.md): "Ambient Occlusion", not "AO". The menu is the
/// only place a channel is ever named, so the name has to be the real one.
///
/// **Adaptive.** The list is `availability.availableDebugChannels` verbatim — it is not
/// `ViewMode.base + DebugChannel.allCases` filtered here, and there is no `if` in this file that
/// mentions a channel. A file with no clearcoat map simply has no Clearcoat row; nothing is shown
/// disabled. That keeps the rule in one place (`Availability`) where a later engine adapter
/// answers it from real data instead of every menu re-deriving it.
///
/// Icon + current title + DS chevron (`DSGlassMenuButton.titled`). Shortcuts come from
/// `DS.Shortcuts` so they cannot collide with camera presets.
struct ViewModeMenu<Capabilities: Availability, Viewport: ViewportController>: View {
    var availability: Capabilities
    var viewport: Viewport

    var body: some View {
        DSGlassMenuButton(
            "View mode",
            systemImage: Self.symbol(for: viewport.viewMode),
            style: .titled(ViewModeMenuChrome.settledTitle(for: viewport.viewMode)),
            isEngaged: viewport.viewMode != .shaded
        ) {
            DSInlineMenuPicker("View mode", selection: mode) {
                ForEach(availability.availableDebugChannels) { mode in
                    Text(mode.title)
                        .tag(mode)
                        .keyboardShortcutIfAvailable(viewModeShortcut(for: mode))
                }
            }
        }
        .contentTransition(.identity)
    }

    private var mode: Binding<ViewMode> {
        Binding(get: { viewport.viewMode }, set: { viewport.setViewMode($0) })
    }

    private func viewModeShortcut(for mode: ViewMode) -> KeyboardShortcut? {
        DS.Shortcuts.ViewMode(rawValue: mode.id).map { DS.Shortcuts.viewMode($0) }
    }

    /// One glyph per family, matching the wireframes: the shaded sphere for Shaded, a grid for
    /// Wireframe, and the mesh cube for any channel (`Inspect@2x.png` on Normals).
    static func symbol(for mode: ViewMode) -> String {
        switch mode {
        case .shaded: "circle.lefthalf.filled"
        case .wireframe: "grid"
        case .channel: "cube"
        }
    }
}

/// Settled view-mode chip copy. The glass `isEngaged` animation must not interpolate this
/// string — HIG interpolate/numericText on "Shaded"→"Wireframe" paints both names at once.
public enum ViewModeMenuChrome {
    /// Mode names are not numbers. The chip snaps; it does not interpolate glyphs.
    public static let interpolatesTitle = false

    public static func settledTitle(for mode: ViewMode) -> String {
        mode.title
    }
}

// MARK: - Previews

private struct ViewModeMenuPreviewHost: View {
    var availability: MockAvailability
    @State private var viewport: MockViewportController

    init(availability: MockAvailability = MockAvailability(), viewport: MockViewportController) {
        self.availability = availability
        _viewport = State(initialValue: viewport)
    }

    var body: some View {
        PreviewCanvas(width: 180, height: 64, background: .canvas) {
            DSGlassIsland {
                ViewModeMenu(availability: availability, viewport: viewport)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

#Preview("shaded", traits: .fixedLayout(width: 180, height: 64)) {
    ViewModeMenuPreviewHost(viewport: MockViewportController())
}

#Preview("wireframe", traits: .fixedLayout(width: 180, height: 64)) {
    ViewModeMenuPreviewHost(viewport: MockViewportController(viewMode: .wireframe))
}

#Preview("normals channel", traits: .fixedLayout(width: 180, height: 64)) {
    ViewModeMenuPreviewHost(viewport: MockViewportController(viewMode: .channel(.normals)))
}
