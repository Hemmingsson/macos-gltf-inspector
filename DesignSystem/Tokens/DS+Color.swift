import AppKit
import SwiftUI

public extension DS {
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
        public static let textPrimary = HierarchicalShapeStyle.primary

        /// Secondary labels: subtitles, field names, readings. SwiftUI `.secondary`
        /// (HIG › Color › "secondaryLabel").
        public static let textSecondary = HierarchicalShapeStyle.secondary

        /// Tertiary labels: section headers, hidden rows. SwiftUI `.tertiary`
        /// (HIG › Color › "tertiaryLabel").
        public static let textTertiary = HierarchicalShapeStyle.tertiary

        /// Quaternary labels: watermark-level text and disabled glyph hints. SwiftUI `.quaternary`
        /// (HIG › Color › "quaternaryLabel").
        public static let textQuaternary = HierarchicalShapeStyle.quaternary

        // MARK: Accent

        /// The user's accent colour (System Settings › Appearance › Accent colour).
        /// SwiftUI `Color.accentColor` (HIG › Color › "App accent colors").
        public static let accent = SwiftUI.Color.accentColor

        /// Background wash behind a selected custom row: `accent` at 14 %.
        /// Native `List` selection needs no token; this is only for rows that cannot use it
        /// (HIG › Color › "selected content background").
        public static let selectionFill = SwiftUI.Color.accentColor.opacity(0.14)

        /// Label / glyph colour inside a selected custom row. SwiftUI `TintShapeStyle` (`.tint`),
        /// so it follows the accent and any local `.tint(_:)` override.
        public static let selectionText = TintShapeStyle.tint

        // MARK: Surfaces

        /// Hairlines between panes and inside cards. AppKit `NSColor.separatorColor`
        /// (HIG › Color › "separator"); Increase Contrast strengthens it automatically.
        public static let separator = SwiftUI.Color(nsColor: .separatorColor)

        /// Opaque ground for boxed controls and value cells. AppKit
        /// `NSColor.controlBackgroundColor` (HIG › Color › "controlBackgroundColor").
        public static let controlBackground = SwiftUI.Color(nsColor: .controlBackgroundColor)

        /// Fill for cards, chips and value boxes that sit on glass or a pane. SwiftUI
        /// `HierarchicalShapeStyle.quinary` — the quietest vibrant fill; use `controlBackground`
        /// when the fill must be opaque.
        public static let cardFill = HierarchicalShapeStyle.quinary

        /// The window ground. AppKit `NSColor.windowBackgroundColor`
        /// (HIG › Color › "windowBackgroundColor").
        public static let windowBackground = SwiftUI.Color(nsColor: .windowBackgroundColor)

        // MARK: Status

        /// Valid / succeeded. System green (`NSColor.systemGreen`, HIG › Color › "System colors").
        public static let success = SwiftUI.Color.green
        /// Warning / lossy. System orange (`NSColor.systemOrange`).
        public static let warning = SwiftUI.Color.orange
        /// Error / failed. System red (`NSColor.systemRed`).
        public static let error = SwiftUI.Color.red

        /// Opacity of the tinted status fills — the same wash strength as `selectionFill`.
        public static let statusFillOpacity: Double = 0.14

        /// Badge / card background for `success`.
        public static let successFill = success.opacity(statusFillOpacity)
        /// Badge / card background for `warning`.
        public static let warningFill = warning.opacity(statusFillOpacity)
        /// Badge / card background for `error`.
        public static let errorFill = error.opacity(statusFillOpacity)

        // MARK: Meaning-colours (fixed on purpose)

        /// glTF role tints. Fixed vocabulary — a camera *is* blue whatever the user's accent —
        /// so these do not follow `accent` (DESIGN.md › "Color = meaning").
        /// Values match `PreviewUI.Theme` so the look is unchanged.
        public enum Role {
            /// Mesh nodes.
            public static let mesh = SwiftUI.Color.dsDynamic(light: 0x6E6E73, dark: 0xA0A0A6)
            /// Cameras.
            public static let camera = SwiftUI.Color.dsDynamic(light: 0x0A84FF, dark: 0x4CA8FF)
            /// Punctual lights.
            public static let light = SwiftUI.Color.dsDynamic(light: 0xF5A623, dark: 0xFFC04D)
            /// Materials.
            public static let material = SwiftUI.Color.dsDynamic(light: 0xA06BD6, dark: 0xC29BEC)
            /// Animations.
            public static let animation = SwiftUI.Color.dsDynamic(light: 0x34C759, dark: 0x30D158)
        }

        /// Axis colours for the orientation and origin gizmos (X red, Y green, Z blue — the DCC
        /// convention). sRGB literals, identical in both appearances; values match
        /// `PreviewUI.OverlayMetrics`.
        public enum Axis {
            /// X axis.
            public static let x = SwiftUI.Color(red: 0xE2 / 255, green: 0x56 / 255, blue: 0x4A / 255)
            /// Y axis.
            public static let y = SwiftUI.Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
            /// Z axis.
            public static let z = SwiftUI.Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
        }

        /// What the backdrop swatches paint. Fixed across appearances: a "White" backdrop is white
        /// at night too — these are the colour the *canvas* takes, not chrome.
        public enum Backdrop {
            /// White backdrop.
            public static let white = SwiftUI.Color.dsDynamic(light: 0xFFFFFF, dark: 0xFFFFFF)
            /// Charcoal backdrop.
            public static let dark = SwiftUI.Color.dsDynamic(light: 0x2C2C2E, dark: 0x2C2C2E)
            /// Dark square of the "None" checkerboard (the light square is `white`). Checkerboard
            /// means *no* backdrop and reads that way only as light-grey-on-white.
            public static let checker = SwiftUI.Color.dsDynamic(light: 0xDCDCE0, dark: 0xDCDCE0)
        }

        /// The flat canvas ground behind the model viewport. Values match `PreviewUI.Theme`.
        public enum Canvas {
            /// Flat viewport colour — the fallback ground for anything drawn over the canvas.
            public static let ground = SwiftUI.Color.dsDynamic(light: 0xECEEF1, dark: 0x1A1B1D)

            /// The placeholder canvas gradient:
            /// `radial-gradient(120% 90% at 50% 30%, #f6f7f9 0%, ground 70%, #e3e5e9 100%)`.
            ///
            /// SwiftUI `EllipticalGradient` (not `RadialGradient`) because the extents are
            /// fractions of the box, so it stays correct at every window size. `0.6` = a 120 %
            /// diameter.
            public static var gradient: EllipticalGradient {
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
