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
struct ViewModeMenu<Capabilities: Availability, Viewport: ViewportController>: View {
    var availability: Capabilities
    var viewport: Viewport

    var body: some View {
        Menu {
            // An inline `Picker` rather than hand-rolled `Button`s: AppKit draws the checkmark
            // column, the selected row, and keyboard navigation for free, and the selection stays
            // one value instead of a comparison repeated per row.
            Picker("View mode", selection: mode) {
                ForEach(availability.availableDebugChannels) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            PillMenuLabel(
                symbol: Self.symbol(for: viewport.viewMode),
                title: viewport.viewMode.title,
                isEngaged: viewport.viewMode != .shaded
            )
        }
        .menuStyle(.borderlessButton)
        // The chip draws its own chevron, so the style's indicator would be a second one.
        .menuIndicator(.hidden)
        // Otherwise the menu claims all the width the pill's HStack will give it.
        .fixedSize()
        .help("View mode")
        .accessibilityLabel("View mode")
        .accessibilityValue(viewport.viewMode.title)
    }

    private var mode: Binding<ViewMode> {
        Binding(get: { viewport.viewMode }, set: { viewport.setViewMode($0) })
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
