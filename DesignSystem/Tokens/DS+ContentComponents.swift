import CoreGraphics

public extension DS.Metrics {
    /// Narrowest a popover panel may get (`DSPopoverPanel`). Popover content is flexible: the
    /// system sizes the popover to the panel's ideal width, never a fixed frame.
    static let popoverMinWidth: CGFloat = 240

    /// Width a popover panel asks for when nothing constrains it (`DSPopoverPanel`).
    static let popoverIdealWidth: CGFloat = 260

    /// Stroke of boxed read-only cells and cards (`DSValueCell`, `DSDocumentCard`). Drawn with
    /// `strokeBorder` in `DS.Color.separator`, so Increase Contrast strengthens the colour, not
    /// the width. Matches `DS.Metrics.hairline`.
    static let cellStrokeWidth: CGFloat = 1

    /// Side of the fixed glyph box of a `DSTypeIcon`, so row titles line up whatever each
    /// symbol's natural width. Scaled with the text size via `@ScaledMetric`. Matches
    /// `PreviewUI.OutlinerTreeMetrics.iconSize`.
    static let typeIcon: CGFloat = 16

    /// Minimum width of the short axis label ("P", "R", "S") in a `DSVectorRow`, so the value
    /// cells of stacked rows line up. Scaled with the text size via `@ScaledMetric`.
    static let vectorLabelWidth: CGFloat = 14
}
