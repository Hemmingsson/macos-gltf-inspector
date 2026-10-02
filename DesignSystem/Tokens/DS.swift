import AppKit
import SwiftUI

/// The glTF Inspector design system: every semantic token hangs off this one namespace.
///
/// Tokens are *roles*, not values. Each resolves to a SwiftUI / AppKit system value (text styles,
/// hierarchical shape styles, semantic `NSColor`s, `Glass` variants) so appearance, accent colour,
/// text size and accessibility settings come from the OS for free. The only fixed literals are the
/// meaning-colours in `DS.Color` (glTF role tints, axes, backdrops, canvas grounds), which encode
/// information and must not follow the user's accent.
///
/// `DesignSystem` has no dependencies: it never imports `PreviewUI`. Where a token is keyed by a
/// PreviewUI concept (view modes, camera presets) it defines a mirroring enum whose raw values
/// match the seam's, so callers map with `init(rawValue:)`.
///
/// Inside `DS` the nested `Color` / `Font` / `Glass` enums shadow the SwiftUI types of the same name;
/// token files therefore spell the SwiftUI types out (`SwiftUI.Color`, `SwiftUI.Font`, …).
public enum DS {}

// MARK: - Internal helpers

extension SwiftUI.Color {
    /// A colour that resolves per appearance through AppKit, so one token serves light and dark and
    /// follows a live System Appearance switch. SwiftUI has no `Color(light:dark:)`.
    ///
    /// Internal on purpose: a public `Color.dsDynamic` would collide with any future
    /// `Color(light:dark:)` helper at call sites.
    static func dsDynamic(light: NSColor, dark: NSColor) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Opaque `#rrggbb` convenience for the fixed meaning-colours only.
    static func dsDynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
        dsDynamic(light: NSColor(dsSRGBHex: light), dark: NSColor(dsSRGBHex: dark))
    }
}

extension NSColor {
    convenience init(dsSRGBHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
