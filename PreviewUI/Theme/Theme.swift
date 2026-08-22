import SwiftUI
import AppKit

/// The one source of truth for colour and frame metrics.
///
/// Light tokens are the design palette (chrome behind, canvas back, text2 quieter than text,
/// text3 quieter still). Dark counterparts keep those same relationships.
///
/// Views must never hard-code a colour: every surface, hairline, label and glTF-type tint comes
/// from here, so appearance switches for free and a palette tweak is one edit.
enum Theme {

    // MARK: Surfaces

    /// `--chrome` — the sidebars, the inspector, and the window ground.
    static let chrome = Color.dynamic(light: 0xF4F4F6, dark: 0x1F1F21)

    /// `--canvas` — the flat viewport colour behind an opaque canvas. `canvasGradient` is what
    /// the placeholder actually paints; this is the fallback ground for anything drawn over it.
    static let canvas = Color.dynamic(light: 0xECEEF1, dark: 0x1A1B1D)

    /// `radial-gradient(120% 90% at 50% 30%, #f6f7f9 0%, var(--canvas) 70%, #e3e5e9 100%)`.
    ///
    /// `EllipticalGradient` (not `RadialGradient`) because the CSS extents are percentages of
    /// the box: a fraction stays correct at every window size, where a fixed `endRadius` would
    /// band on a wide window and clip on a narrow one. `0.6` = a 120% diameter.
    static var canvasGradient: EllipticalGradient {
        EllipticalGradient(
            stops: [
                .init(color: .dynamic(light: 0xF6F7F9, dark: 0x26272A), location: 0.0),
                .init(color: canvas, location: 0.7),
                .init(color: .dynamic(light: 0xE3E5E9, dark: 0x0F1012), location: 1.0)
            ],
            center: UnitPoint(x: 0.5, y: 0.3),
            startRadiusFraction: 0,
            endRadiusFraction: 0.6
        )
    }

    /// A raised block sitting on `chrome` — the sidebar's document header card.
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x2B2B2E)

    // MARK: Lines

    /// `--border` — panel edges and the column hairlines.
    static let border = Color.dynamic(light: .srgbBlack(0.10), dark: .srgbWhite(0.12))

    /// `--hair` — the quieter rule used inside a panel (section separators, card outlines).
    static let hair = Color.dynamic(light: .srgbBlack(0.06), dark: .srgbWhite(0.08))

    // MARK: Text

    /// `--text` — primary labels.
    static let text = Color.dynamic(light: 0x1D1D1F, dark: 0xF2F2F5)
    /// `--text2` — secondary labels (subtitles, field labels).
    static let text2 = Color.dynamic(light: 0x86868B, dark: 0x9E9EA4)
    /// `--text3` — tertiary labels (uppercase section headers).
    static let text3 = Color.dynamic(light: 0xA6A6AB, dark: 0x8C8C92)
    /// Readout values in the inspector (mono digits between `text` and `text2`).
    static let textValue = Color.dynamic(light: 0x55555B, dark: 0xC0C0C6)

    // MARK: Accent

    /// `--accent` — the wireframe's fixed blue. Deliberately not `.controlAccentColor`: the
    /// glTF-type tints are a fixed vocabulary (camera *is* blue), and a user accent of orange
    /// would collide with the light tint.
    static let accent = Color.dynamic(light: 0x0A84FF, dark: 0x0A84FF)

    /// `--sel` — the selected outliner row's background.
    static let selection = Color.dynamic(
        light: .init(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 0.12),
        dark: .init(srgbRed: 0.039, green: 0.518, blue: 1.0, alpha: 0.28)
    )

    /// Label and icon colour *inside* a selected row.
    /// A deeper blue than `accent`, because `accent` on a 12%-alpha `accent` fill has almost no
    /// contrast; dark inverts the relationship for the same reason.
    static let selectionText = Color.dynamic(light: 0x0060DF, dark: 0x9AC9FF)

    // MARK: Canvas pills

    /// `.tbtn { color: #494950 }` — the resting glyph inside a toolbar pill. Deliberately its own
    /// token: it sits between `text` and `text2`, and it is read against *glass*, not against
    /// `chrome`, so it cannot borrow either of them without going muddy on one appearance.
    static let glyph = Color.dynamic(light: 0x494950, dark: 0xD5D5DA)

    /// `.tbtn.on { color: #fff }` — the glyph on an accent fill. Fixed in both appearances,
    /// because the fill it sits on is fixed too.
    static let onGlyph = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)

    /// `background: rgba(0,0,0,0.045)` — the quiet fill behind a pill's *menu* chip (view mode).
    /// A menu is not a toggle, so it never takes the accent; it needs the faintest possible
    /// "this is pressable" ground instead.
    static let controlFill = Color.dynamic(light: .srgbBlack(0.045), dark: .srgbWhite(0.07))

    // MARK: Backdrops

    /// What the `BackdropStyle` swatches paint. Fixed across appearances on purpose: a "White"
    /// backdrop is white at night too — these are the colour the *canvas* takes, not chrome.
    static let backdropWhite = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Charcoal backdrop swatch.
    static let backdropDark = Color.dynamic(light: 0x2C2C2E, dark: 0x2C2C2E)
    /// The dark square of the "None" swatch's checkerboard (`#dcdce0`); the light square is
    /// `backdropWhite`. Checkerboard means *no* backdrop, and it reads that way only while it
    /// keeps the conventional light-grey-on-white.
    static let backdropChecker = Color.dynamic(light: 0xDCDCE0, dark: 0xDCDCE0)

    // MARK: glTF type tints

    /// `--mesh`
    static let mesh = Color.dynamic(light: 0x6E6E73, dark: 0xA0A0A6)
    /// `--camera`
    static let camera = Color.dynamic(light: 0x0A84FF, dark: 0x4CA8FF)
    /// `--light`
    static let light = Color.dynamic(light: 0xF5A623, dark: 0xFFC04D)
    /// `--material`
    static let material = Color.dynamic(light: 0xA06BD6, dark: 0xC29BEC)
    /// `--animation`
    static let animation = Color.dynamic(light: 0x34C759, dark: 0x30D158)

    // MARK: Frame metrics

    /// Left column, fixed (Main-html `aside` width).
    static let sidebarWidth: CGFloat = 248
    /// Right column, fixed (Main-html trailing `aside` width).
    static let inspectorWidth: CGFloat = 288
    /// Column separator. A `Divider()` reads far heavier than this on macOS.
    static let hairlineWidth: CGFloat = 1
    /// Unified top chrome band: traffic lights, sidebar toggle, canvas islands, inspector actions.
    /// Controls top-align to `trafficLightCenterY` via `ChromeMetrics.bandTopInset`.
    static let topChromeHeight: CGFloat = 52
    /// Shared centerline (from the window top) for the whole top chrome band: the system traffic
    /// lights, the pane toggles, the canvas pills, and the inspector actions all center here. A
    /// `.hiddenTitleBar` window pins the lights near y≈16; `TrafficLightConfigurator` moves them
    /// down to this line so the band breathes above instead of sitting flush to the window edge.
    static let trafficLightCenterY: CGFloat = 26
    /// Leading clearance past the three system lights to the sidebar toggle.
    static let trafficLightLeadingClearance: CGFloat = 78
    /// Shared hit target for chrome circles and pill `.tbtn`s (Sketch island scale).
    static let chromeControlSize: CGFloat = 30
}

extension Color {
    /// SwiftUI has no `Color(light:dark:)`. Resolve per appearance through AppKit instead, so
    /// one token serves both themes and follows a live System Appearance switch.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    /// Convenience for the opaque `#rrggbb` tokens.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: NSColor(srgbHex: light), dark: NSColor(srgbHex: dark))
    }
}

private extension NSColor {
    static func srgbBlack(_ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha)
    }

    static func srgbWhite(_ alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
    }

    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
