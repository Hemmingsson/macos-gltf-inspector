import CoreGraphics

extension DS {
    /// 4-pt spacing scale (HIG › Layout: align to a consistent grid; SwiftUI `padding` /
    /// `spacing` arguments). Prefer the system default spacing where a stack has no opinion.
    enum Spacing {
        /// 2 pt — hairline gaps (icon to badge).
        static let xxs: CGFloat = 2
        /// 4 pt — tight gaps inside a control.
        static let xs: CGFloat = 4
        /// 6 pt — label to value.
        static let s: CGFloat = 6
        /// 8 pt — default gap between related controls.
        static let m: CGFloat = 8
        /// 12 pt — between groups.
        static let l: CGFloat = 12
        /// 16 pt — between sections.
        static let xl: CGFloat = 16
        /// 24 pt — between major regions.
        static let xxl: CGFloat = 24

        /// Inset of content from a pane edge (sidebar, inspector).
        static let paneInset: CGFloat = 8
    }

    /// Corner radii. Glass controls use `.capsule` / `.circle` shapes rather than a radius, and
    /// nested shapes prefer `ConcentricRectangle` / `.containerShape(_:)` (HIG › Layout ›
    /// "Concentricity") where the container provides one.
    enum Radius {
        /// 6 pt — cells and chips.
        static let small: CGFloat = 6
        /// 8 pt — rows.
        static let medium: CGFloat = 8
        /// 12 pt — cards.
        static let large: CGFloat = 12
        /// 18 pt — floating panes.
        static let pane: CGFloat = 18
    }

    /// Fixed metrics for custom chrome. Standard controls use `controlSize(_:)`, never a fixed
    /// height (HIG › Buttons › "Sizes").
    enum Metrics {
        /// Side of a glass cluster button (icon-only, circle).
        static let glassControl: CGFloat = 32
        /// Width of a glass control that carries a menu chevron.
        static let glassControlWide: CGFloat = 46
        /// Gap between islands inside a glass cluster.
        static let clusterSpacing: CGFloat = 8
        /// Side of a backdrop swatch.
        static let swatch: CGFloat = 20

        /// Ideal sidebar column width (`navigationSplitViewColumnWidth(min:ideal:max:)`).
        static let sidebarWidth: CGFloat = 248
        /// Allowed sidebar column widths.
        static let sidebarWidthRange: ClosedRange<CGFloat> = 220...520

        /// Ideal inspector column width (`inspectorColumnWidth(min:ideal:max:)`).
        static let inspectorWidth: CGFloat = 288
        /// Allowed inspector column widths.
        static let inspectorWidthRange: ClosedRange<CGFloat> = 260...560

        /// Inset of Stage / Camera clusters from the canvas edge.
        static let canvasClusterInset: CGFloat = 14
        /// Gap between a collapsed-pane restore control and the nearest cluster.
        static let toolbarClearance: CGFloat = 20
        /// Height of the overlay band that shares the traffic-light centerline.
        static let toolbarBandHeight: CGFloat = 52
        /// Vertical center of the system traffic lights, from the top of the window.
        static let toolbarCenterY: CGFloat = 26
        /// Leading space reserved for traffic lights when the sidebar is collapsed.
        static let trafficLightLeadingClearance: CGFloat = 78
    }
}
