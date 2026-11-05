import AppKit
import SwiftUI

/// The app's layout and colour decisions. Text styles, label colours and the accent come straight
/// from SwiftUI (`.body`, `.secondary`, `.accentColor`); only values the system does not provide
/// live here. Nested `Color` / `Glass` shadow the SwiftUI types, so this file spells those out.
enum DS {
    /// 4-pt spacing scale.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 6
        static let m: CGFloat = 8
        static let l: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        /// Content inset from a pane edge (sidebar, inspector).
        static let paneInset: CGFloat = 8
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 8
        static let large: CGFloat = 12
        static let pane: CGFloat = 18
    }

    enum Metrics {
        static let hairline: CGFloat = 1
        /// Hit area of the navigation gizmo on the canvas.
        static let navigationGizmoSize: CGFloat = 76
        /// Side of an icon-only glass button.
        static let glassControl: CGFloat = 32
        /// Width of a glass button that carries a menu chevron.
        static let glassControlWide: CGFloat = 46
        /// Gap between islands in a glass cluster; also the glass container spacing.
        static let clusterSpacing: CGFloat = 8
        static let islandDividerHeight: CGFloat = 16

        static let swatch: CGFloat = 20
        static let swatchRingWidth: CGFloat = 1.5
        static let swatchRingGap: CGFloat = 2
        static let checkerboardCell: CGFloat = 4

        static let popoverMinWidth: CGFloat = 240
        static let popoverIdealWidth: CGFloat = 260
        /// Scaled with text size via `@ScaledMetric` where used.
        static let typeIcon: CGFloat = 16
        static let outlineIndent: CGFloat = 16
        static let vectorLabelWidth: CGFloat = 14

        static let sidebarWidth: CGFloat = 248
        static let sidebarWidthRange: ClosedRange<CGFloat> = 220...520
        static let inspectorWidth: CGFloat = 288
        static let inspectorWidthRange: ClosedRange<CGFloat> = 260...560

        /// Inset of the canvas clusters from the canvas edge.
        static let canvasClusterInset: CGFloat = 14
        /// Gap between a collapsed-pane restore control and the nearest cluster.
        static let toolbarClearance: CGFloat = 20
        /// The overlay band that shares the traffic lights' centre line.
        static let toolbarBandHeight: CGFloat = 52
        static let toolbarCenterY: CGFloat = 26
        /// Room for the traffic lights when the sidebar is collapsed.
        static let trafficLightLeadingClearance: CGFloat = 78
    }

    enum Color {
        static let separator = SwiftUI.Color(nsColor: .separatorColor)
        static let controlBackground = SwiftUI.Color(nsColor: .controlBackgroundColor)
        static let windowBackground = SwiftUI.Color(nsColor: .windowBackgroundColor)
        /// A layer row whose node is under the canvas pointer (pre-selection), below the
        /// selection highlight's strength.
        static let pointedRowFill = SwiftUI.Color.accentColor.opacity(0.14)

        /// Tint over the sidebar and inspector glass: translucent so the canvas reads through.
        static let paneFill = SwiftUI.Color.dynamic(
            light: NSColor.white.withAlphaComponent(0.82),
            dark: NSColor(white: 0.12, alpha: 0.82)
        )

        /// glTF role tints. Fixed meaning, so they ignore the user's accent.
        enum Role {
            static let mesh = SwiftUI.Color.dynamic(light: 0x6E6E73, dark: 0xA0A0A6)
            static let camera = SwiftUI.Color.dynamic(light: 0x0A84FF, dark: 0x4CA8FF)
            static let light = SwiftUI.Color.dynamic(light: 0xF5A623, dark: 0xFFC04D)
            static let material = SwiftUI.Color.dynamic(light: 0xA06BD6, dark: 0xC29BEC)
            static let animation = SwiftUI.Color.dynamic(light: 0x34C759, dark: 0x30D158)
        }

        /// Gizmo axes: X red, Y green, Z blue.
        enum Axis {
            static let x = SwiftUI.Color(red: 0xE2 / 255, green: 0x56 / 255, blue: 0x4A / 255)
            static let y = SwiftUI.Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
            static let z = SwiftUI.Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
            /// Negative axis ends on the navigation gizmo.
            static let negative = SwiftUI.Color.secondary
        }

        /// What the backdrop swatches paint; the same in both appearances.
        enum Backdrop {
            static let white = SwiftUI.Color.white
            static let dark = SwiftUI.Color(nsColor: NSColor(srgbHex: 0x2C2C2E))
            /// Dark square of the "None" checkerboard.
            static let checker = SwiftUI.Color(nsColor: NSColor(srgbHex: 0xDCDCE0))
        }

        enum Canvas {
            static let ground = SwiftUI.Color.dynamic(light: 0xECEEF1, dark: 0x1A1B1D)
            /// Placeholder ground: an elliptical gradient so it scales with the window.
            static var gradient: EllipticalGradient {
                EllipticalGradient(
                    stops: [
                        .init(color: .dynamic(light: 0xF6F7F9, dark: 0x26272A), location: 0.0),
                        .init(color: ground, location: 0.7),
                        .init(color: .dynamic(light: 0xE3E5E9, dark: 0x0F1012), location: 1.0)
                    ],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.6
                )
            }
        }
    }

    /// Liquid Glass for the canvas clusters and HUDs. Never glass on glass.
    enum Glass {
        static var control: SwiftUI.Glass { .regular.interactive() }
        /// "On" state: a light accent wash; the glyph carries the full tint.
        static var controlEngaged: SwiftUI.Glass { .regular.tint(.accentColor.opacity(0.18)).interactive() }
        static var hud: SwiftUI.Glass { .regular }
    }

    enum Motion {
        /// Chrome transitions; `nil` under Reduce Motion.
        static func chrome(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.15)
        }
    }
}

extension View {
    /// Uppercase section label (SCENE, MATERIALS).
    func dsSectionHeader() -> some View {
        font(.subheadline.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

/// Whether a layer row draws, and why not. `hiddenByParent` and `hiddenInFile` are read-only
/// states of the row; `hidden` is the window's own choice.
enum DSVisibility: Sendable, Equatable {
    case visible
    /// Hidden in this window.
    case hidden
    /// Its own visibility is fine, but an ancestor is hidden or another node is soloed.
    case hiddenByParent
    /// Authored as hidden (`KHR_node_visibility`). Shown, not toggled.
    case hiddenInFile
}

extension SwiftUI.Color {
    /// One colour per appearance, resolved by AppKit so a live appearance switch follows.
    static func dynamic(light: NSColor, dark: NSColor) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static func dynamic(light: UInt32, dark: UInt32) -> SwiftUI.Color {
        dynamic(light: NSColor(srgbHex: light), dark: NSColor(srgbHex: dark))
    }
}

extension NSColor {
    convenience init(srgbHex hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
