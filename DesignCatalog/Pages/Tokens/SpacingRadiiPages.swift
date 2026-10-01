import DesignSystem
import SwiftUI

/// `DS.Spacing` rulers at actual size, plus every fixed `DS.Metrics` value.
struct SpacingPage: View {
    private let spacing: [(String, CGFloat, String)] = [
        ("xxs", DS.Spacing.xxs, "hairline gaps"),
        ("xs", DS.Spacing.xs, "inside a control"),
        ("s", DS.Spacing.s, "label to value"),
        ("m", DS.Spacing.m, "related controls"),
        ("l", DS.Spacing.l, "between groups"),
        ("xl", DS.Spacing.xl, "between sections"),
        ("xxl", DS.Spacing.xxl, "major regions"),
        ("paneInset", DS.Spacing.paneInset, "content from a pane edge"),
        ("canvasInset", DS.Spacing.canvasInset, "floating controls from the canvas edge")
    ]

    private let metrics: [(String, CGFloat)] = [
        ("glassControl", DS.Metrics.glassControl),
        ("glassControlWide", DS.Metrics.glassControlWide),
        ("clusterSpacing", DS.Metrics.clusterSpacing),
        ("swatch", DS.Metrics.swatch),
        ("swatchRingWidth", DS.Metrics.swatchRingWidth),
        ("swatchRingGap", DS.Metrics.swatchRingGap),
        ("checkerboardCell", DS.Metrics.checkerboardCell),
        ("islandDividerHeight", DS.Metrics.islandDividerHeight),
        ("hairline", DS.Metrics.hairline),
        ("cellStrokeWidth", DS.Metrics.cellStrokeWidth),
        ("typeIcon", DS.Metrics.typeIcon),
        ("vectorLabelWidth", DS.Metrics.vectorLabelWidth),
        ("popoverMinWidth", DS.Metrics.popoverMinWidth),
        ("popoverIdealWidth", DS.Metrics.popoverIdealWidth),
        ("sidebarWidth", DS.Metrics.sidebarWidth),
        ("inspectorWidth", DS.Metrics.inspectorWidth),
        ("canvasMinWidth", DS.Metrics.canvasMinWidth),
        ("canvasClusterInset", DS.Metrics.canvasClusterInset),
        ("toolbarClearance", DS.Metrics.toolbarClearance),
        ("toolbarBandHeight", DS.Metrics.toolbarBandHeight),
        ("toolbarCenterY", DS.Metrics.toolbarCenterY),
        ("trafficLightLeadingClearance", DS.Metrics.trafficLightLeadingClearance)
    ]

    var body: some View {
        CatalogPageView(page: .spacing) {
            StateGroup(title: "Spacing scale", note: "Bars at actual size; the ×4 bar makes the small steps comparable.") {
                Grid(alignment: .leading, horizontalSpacing: DS.Spacing.xl, verticalSpacing: DS.Spacing.m) {
                    ForEach(spacing, id: \.0) { name, value, use in
                        GridRow {
                            TokenLabel(name: "DS.Spacing.\(name)", role: "\(value.formatted()) pt · \(use)")
                                .frame(width: 300, alignment: .leading)
                            bar(width: value)
                            bar(width: value * 4)
                                .opacity(0.5)
                        }
                    }
                }
            }

            StateGroup(title: "Metrics") {
                VStack(spacing: DS.Spacing.s) {
                    ForEach(metrics, id: \.0) { name, value in
                        DSFactRow("DS.Metrics.\(name)", value: "\(value.formatted()) pt")
                    }
                    DSFactRow(
                        "DS.Metrics.sidebarWidthRange",
                        value: "\(DS.Metrics.sidebarWidthRange.lowerBound.formatted())…\(DS.Metrics.sidebarWidthRange.upperBound.formatted()) pt"
                    )
                    DSFactRow(
                        "DS.Metrics.inspectorWidthRange",
                        value: "\(DS.Metrics.inspectorWidthRange.lowerBound.formatted())…\(DS.Metrics.inspectorWidthRange.upperBound.formatted()) pt"
                    )
                }
                .frame(maxWidth: 520)
            }
        }
    }

    private func bar(width: CGFloat) -> some View {
        Rectangle()
            .fill(DS.Color.accent)
            .frame(width: width, height: 12)
            .accessibilityHidden(true)
    }
}

/// `DS.Radius` samples at actual size.
struct RadiiPage: View {
    private let radii: [(String, CGFloat, String)] = [
        ("small", DS.Radius.small, "cells and chips"),
        ("medium", DS.Radius.medium, "rows"),
        ("large", DS.Radius.large, "cards"),
        ("pane", DS.Radius.pane, "floating panes")
    ]

    var body: some View {
        CatalogPageView(page: .radii) {
            StateGroup(
                title: "Radii",
                note: "Continuous corners. Glass controls use capsule / circle shapes instead of a radius."
            ) {
                HStack(alignment: .top, spacing: DS.Spacing.xxl) {
                    ForEach(radii, id: \.0) { name, value, use in
                        VStack(alignment: .leading, spacing: DS.Spacing.m) {
                            RoundedRectangle(cornerRadius: value, style: .continuous)
                                .fill(DS.Color.cardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: value, style: .continuous)
                                        .strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
                                )
                                .frame(width: 120, height: 80)
                            TokenLabel(name: "DS.Radius.\(name)", role: "\(value.formatted()) pt · \(use)")
                        }
                    }
                }
            }

            StateGroup(title: "In context") {
                StateRow("Chip · cell · card · pane") {
                    HStack(spacing: DS.Spacing.l) {
                        DSChip("12 tris")
                        DSValueCell("0.50").frame(width: 72)
                        DSStatusBadge("Valid glTF 2.0", status: .valid).frame(width: 180)
                    }
                }
            }
        }
    }
}
