import SwiftUI

public extension DS {
    /// Type ramp. Every token is a SwiftUI text style (HIG › Typography › "macOS built-in text
    /// styles"), so all of them scale with the user's text-size setting. Never a fixed point size.
    enum Font {
        /// Default reading text: row titles, popover labels. `Font.body` (macOS 13 pt).
        public static let body = SwiftUI.Font.body

        /// Emphasised body: the selected node name, primary actions. `Font.body.weight(.semibold)`.
        public static let bodyEmphasized = SwiftUI.Font.body.weight(.semibold)

        /// Slightly smaller supporting text: fact rows, slider titles. `Font.callout` (macOS 12 pt).
        public static let callout = SwiftUI.Font.callout

        /// Subtitles under a title. `Font.subheadline` (macOS 11 pt).
        public static let subheadline = SwiftUI.Font.subheadline

        /// Captions and chip labels. `Font.caption` (macOS 10 pt).
        public static let caption = SwiftUI.Font.caption

        /// The smallest legible text: gizmo tags, badge counts. `Font.caption2` (macOS 10 pt).
        public static let micro = SwiftUI.Font.caption2

        /// Pane and card titles. `Font.title3.weight(.semibold)` (macOS 15 pt).
        public static let title = SwiftUI.Font.title3.weight(.semibold)

        /// Uppercase section labels (SCENE, MATERIALS, GEOMETRY). `Font.subheadline` semibold; apply
        /// with `.dsSectionHeader()` so the case and tracking come along.
        public static let sectionHeader = SwiftUI.Font.subheadline.weight(.semibold)

        /// Tracking for `sectionHeader`: opens up small uppercase text (HIG › Typography ›
        /// "Tracking"). Matches today's inspector section header.
        public static let sectionHeaderTracking: CGFloat = 0.5

        /// Numeric readouts (transforms, stats, slider readings). `Font.callout.monospacedDigit()`
        /// so columns of digits do not jitter as values change.
        public static let value = SwiftUI.Font.callout.monospacedDigit()
    }
}

public extension View {
    /// Section-header typography: `DS.Font.sectionHeader`, uppercased, with
    /// `DS.Font.sectionHeaderTracking`. Colour and padding are the caller's (or `DSSectionHeader`'s).
    func dsSectionHeader() -> some View {
        font(DS.Font.sectionHeader)
            .textCase(.uppercase)
            .tracking(DS.Font.sectionHeaderTracking)
    }
}
