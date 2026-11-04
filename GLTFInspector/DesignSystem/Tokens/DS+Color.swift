import AppKit
import SwiftUI

extension DS {
    /// Colour roles.
    ///
    /// Text and fills are hierarchical `ShapeStyle`s, not flat colours, so they keep their
    /// vibrancy on Liquid Glass and adapt to Increase Contrast. Surfaces map to AppKit semantic
    /// colours. Only the nested meaning-colour namespaces (`Role`, `Axis`, `Backdrop`, `Canvas`)
    /// are fixed literals.
    enum Color {

        // MARK: Text

        /// Primary labels. SwiftUI `HierarchicalShapeStyle.primary`
        /// (HIG › Color › "label" — primary content).
        static let textPrimary = HierarchicalShapeStyle.primary

        /// Secondary labels: subtitles, field names, readings. SwiftUI `.secondary`
        /// (HIG › Color › "secondaryLabel").
        static let textSecondary = HierarchicalShapeStyle.secondary

        /// Tertiary labels: section headers, hidden rows. SwiftUI `.tertiary`
        /// (HIG › Color › "tertiaryLabel").
        static let textTertiary = HierarchicalShapeStyle.tertiary

        /// Quaternary labels: watermark-level text and disabled glyph hints. SwiftUI `.quaternary`
        /// (HIG › Color › "quaternaryLabel").
        static let textQuaternary = HierarchicalShapeStyle.quaternary

        // MARK: Accent

        /// The user's accent colour (System Settings › Appearance › Accent colour).
        /// SwiftUI `Color.accentColor` (HIG › Color › "App accent colors").
        static let accent = SwiftUI.Color.accentColor

        /// Background wash behind a selected custom row: `accent` at 14 %.
        /// Native `List` selection needs no token; this is only for rows that cannot use it
        /// (HIG › Color › "selected content background").
        static let selectionFill = SwiftUI.Color.accentColor.opacity(0.14)

        /// Filled portion of a read-only factor bar (`DSFactorRow`): `accent` at 45 %, so the
        /// primary-text reading on top stays legible in either appearance.
        static let factorFill = SwiftUI.Color.accentColor.opacity(0.45)

        /// Label / glyph colour inside a selected custom row. SwiftUI `TintShapeStyle` (`.tint`),
        /// so it follows the accent and any local `.tint(_:)` override.
        static let selectionText = TintShapeStyle.tint

        // MARK: Surfaces

        /// Hairlines between panes and inside cards. AppKit `NSColor.separatorColor`
        /// (HIG › Color › "separator"); Increase Contrast strengthens it automatically.
        static let separator = SwiftUI.Color(nsColor: .separatorColor)

        /// Opaque ground for boxed controls and value cells. AppKit
        /// `NSColor.controlBackgroundColor` (HIG › Color › "controlBackgroundColor").
        static let controlBackground = SwiftUI.Color(nsColor: .controlBackgroundColor)

        /// Fill for cards, chips and value boxes that sit on glass or a pane. SwiftUI
        /// `HierarchicalShapeStyle.quinary` — the quietest vibrant fill; use `controlBackground`
        /// when the fill must be opaque.
        static let cardFill = HierarchicalShapeStyle.quinary

        /// The window ground. AppKit `NSColor.windowBackgroundColor`
        /// (HIG › Color › "windowBackgroundColor").
        static let windowBackground = SwiftUI.Color(nsColor: .windowBackgroundColor)

        /// Tint over the sidebar's and inspector's glass: near-white like a design tool's layer panel, but
        /// translucent so the canvas still reads faintly through it.
        static let paneFill = SwiftUI.Color.dsDynamic(
            light: NSColor.white.withAlphaComponent(0.82),
            dark: NSColor(white: 0.12, alpha: 0.82)
        )

        // MARK: Status

        /// Valid / succeeded. System green (`NSColor.systemGreen`, HIG › Color › "System colors").
        static let success = SwiftUI.Color.green
        /// Warning / lossy. System orange (`NSColor.systemOrange`).
        static let warning = SwiftUI.Color.orange
        /// Error / failed. System red (`NSColor.systemRed`).
        static let error = SwiftUI.Color.red

        /// Opacity of the tinted status fills — the same wash strength as `selectionFill`.
        static let statusFillOpacity: Double = 0.14

        /// Badge / card background for `success`.
        static let successFill = success.opacity(statusFillOpacity)
        /// Badge / card background for `warning`.
        static let warningFill = warning.opacity(statusFillOpacity)
        /// Badge / card background for `error`.
        static let errorFill = error.opacity(statusFillOpacity)

        // MARK: Meaning-colours (fixed on purpose)

        /// glTF role tints. Fixed vocabulary — a camera *is* blue whatever the user's accent —
        /// so these do not follow `accent` (DESIGN.md › "Color = meaning").
        enum Role {
            static let mesh = SwiftUI.Color.dsDynamic(light: 0x6E6E73, dark: 0xA0A0A6)
            static let camera = SwiftUI.Color.dsDynamic(light: 0x0A84FF, dark: 0x4CA8FF)
            static let light = SwiftUI.Color.dsDynamic(light: 0xF5A623, dark: 0xFFC04D)
            static let material = SwiftUI.Color.dsDynamic(light: 0xA06BD6, dark: 0xC29BEC)
            static let animation = SwiftUI.Color.dsDynamic(light: 0x34C759, dark: 0x30D158)
        }

        /// Axis colours for the orientation and origin gizmos (X red, Y green, Z blue — the DCC
        /// convention). sRGB literals, identical in both appearances.
        enum Axis {
            static let x = SwiftUI.Color(red: 0xE2 / 255, green: 0x56 / 255, blue: 0x4A / 255)
            static let y = SwiftUI.Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
            static let z = SwiftUI.Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        }

        /// What the backdrop swatches paint. Fixed across appearances: a "White" backdrop is white
        /// at night too — these are the colour the *canvas* takes, not chrome.
        enum Backdrop {
            static let white = SwiftUI.Color.dsDynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
            static let dark = SwiftUI.Color.dsDynamic(light: 0x2C2C2E, dark: 0x2C2C2E)
            /// Dark square of the "None" checkerboard (the light square is `white`). Checkerboard
            /// means *no* backdrop and reads that way only as light-grey-on-white.
            static let checker = SwiftUI.Color.dsDynamic(light: 0xDCDCE0, dark: 0xDCDCE0)
        }

        /// The flat canvas ground behind the model viewport.
        enum Canvas {
            /// Flat viewport colour — the fallback ground for anything drawn over the canvas.
            static let ground = SwiftUI.Color.dsDynamic(light: 0xECEEF1, dark: 0x1A1B1D)

            /// The placeholder canvas gradient:
            /// `radial-gradient(120% 90% at 50% 30%, #f6f7f9 0%, ground 70%, #e3e5e9 100%)`.
            ///
            /// SwiftUI `EllipticalGradient` (not `RadialGradient`) because the extents are
            /// fractions of the box, so it stays correct at every window size. `0.6` = a 120 %
            /// diameter.
            static var gradient: EllipticalGradient {
                EllipticalGradient(
                    stops: [
                        .init(color: .dsDynamic(light: 0xF6F7F9, dark: 0x26272A), location: 0.0),
                        .init(color: ground, location: 0.7),
                        .init(color: .dsDynamic(light: 0xE3E5E9, dark: 0x0F1012), location: 1.0)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.6
                )
            }
        }
    }
}
