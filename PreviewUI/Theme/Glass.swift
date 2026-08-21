import SwiftUI

// MARK: - Snapshot flatten switch
//
// Offscreen rasterization (`NSHostingView` + `cacheDisplay` in `SnapshotHarness`) cannot
// reproduce Liquid Glass. Worse: `.buttonStyle(.glassProminent)` paints an **unbounded opaque
// white sheet** that blanks the entire snapshot — not just the pill that used it. Measured on
// macOS 26 with a lone prominent button hosted offscreen.
//
// The snapshot harness sets `\.previewFlattenGlass` to `true` so these helpers substitute a flat
// accent / card treatment. Live windows leave the key at its default (`false`) and keep real
// `.glass` / `.glassProminent` / `.glassEffect`. Do not set the key outside the harness.

private struct PreviewFlattenGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When `true`, glass button styles and pill chrome use flat stand-ins safe for offscreen
    /// snapshots. Default `false` — live windows keep Liquid Glass.
    var previewFlattenGlass: Bool {
        get { self[PreviewFlattenGlassKey.self] }
        set { self[PreviewFlattenGlassKey.self] = newValue }
    }
}

extension View {
    /// `.buttonStyle` is not a `@ViewBuilder`-friendly value across the two glass styles
    /// (`.glass` and `.glassProminent` are different types), so branch on the view instead.
    ///
    /// Cribbed from `Shared/PreviewChromeBar.swift` rather than imported: `PreviewUI` must not
    /// depend on `Shared/` (see the epic's standing constraints).
    ///
    /// When `previewFlattenGlass` is set (snapshot harness only), substitutes `.bordered` /
    /// `.borderedProminent` so offscreen rasterization does not blank the bitmap.
    func previewGlassButtonStyle(prominent: Bool) -> some View {
        modifier(PreviewGlassButtonStyleModifier(prominent: prominent))
    }

    /// A toggle inside a canvas pill (`.tbtn` / `.tbtn.on`).
    ///
    /// Off is always `.plain`: these sit **inside** a pill that is already glass, and glass cannot
    /// sample glass — `.glass` on every button would stack a second material and turn one clean
    /// pill into embossed chips. The wireframe agrees: `.tbtn` has no background until `.on`.
    ///
    /// On uses an **inset** `Theme.selection` wash inside the fixed 30×30 hit target — not
    /// `.glassProminent`. Solid accent slabs grew the pill and shifted neighbours; Sketch-style
    /// chrome keeps geometry constant and only tints the interior.
    ///
    /// Snapshot path uses the same inset wash (no `.glassProminent` sheet — see `PreviewFlattenGlassKey`).
    func pillButtonStyle(active: Bool) -> some View {
        modifier(PillButtonStyleModifier(active: active))
    }
}

private struct PreviewGlassButtonStyleModifier: ViewModifier {
    var prominent: Bool
    @Environment(\.previewFlattenGlass) private var flatten

    @ViewBuilder
    func body(content: Content) -> some View {
        if flatten {
            if prominent {
                content
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            } else {
                content.buttonStyle(.bordered)
            }
        } else if prominent {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.glass)
        }
    }
}

private struct PillButtonStyleModifier: ViewModifier {
    var active: Bool

    func body(content: Content) -> some View {
        // Live and snapshot share the same path: plain + optional inset wash. No
        // `.glassProminent` (layout-growing / snapshot-blanking), and flatten is irrelevant
        // because there is no glass material on the toggle itself.
        //
        // Custom `ButtonStyle` so `configuration.isFocused` can draw an accent ring —
        // `.plain` alone suppresses the system focus ring over glass.
        content.buttonStyle(PillIconButtonStyle(active: active))
    }
}

/// Fixed 30×30 pill glyph button: inset selection wash + accent focus ring.
struct PillIconButtonStyle: ButtonStyle {
    var active: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if active {
                    RoundedRectangle(cornerRadius: PillMetrics.selectionCornerRadius, style: .continuous)
                        .fill(Theme.selection)
                        .padding(PillMetrics.selectionInset)
                }
            }
            .overlay {
                PreviewFocusStroke(shape: .roundedRect(PillMetrics.buttonCornerRadius))
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
