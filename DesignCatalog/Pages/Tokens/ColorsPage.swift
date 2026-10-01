import DesignSystem
import SwiftUI

/// Every `DS.Color` token as a light and a dark swatch, with its name and the system role it
/// resolves to.
struct ColorsPage: View {
    var body: some View {
        CatalogPageView(page: .colors) {
            ForEach(ColorTokenGroup.all) { group in
                StateGroup(title: group.title, note: group.note) {
                    Grid(alignment: .leading, horizontalSpacing: DS.Spacing.l, verticalSpacing: DS.Spacing.m) {
                        GridRow {
                            columnTitle("Light")
                            columnTitle("Dark")
                            columnTitle("Token · resolves to")
                        }
                        ForEach(group.tokens) { token in
                            GridRow {
                                ColorSwatch(token: token).environment(\.colorScheme, .light)
                                ColorSwatch(token: token).environment(\.colorScheme, .dark)
                                TokenLabel(name: token.name, role: token.role)
                            }
                        }
                    }
                }
            }
        }
    }

    private func columnTitle(_ title: String) -> some View {
        Text(title)
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.textTertiary)
    }
}

private struct ColorToken: Identifiable {
    enum Kind {
        /// Painted as a filled swatch on the window ground.
        case fill
        /// Painted as "Aa" text plus a bar, on the window ground.
        case text
    }

    let name: String
    let role: String
    let style: AnyShapeStyle
    var kind: Kind = .fill

    var id: String { name }

    init(_ name: String, _ role: String, _ style: some ShapeStyle, kind: Kind = .fill) {
        self.name = name
        self.role = role
        self.style = AnyShapeStyle(style)
        self.kind = kind
    }
}

private struct ColorTokenGroup: Identifiable {
    let title: String
    var note: String?
    let tokens: [ColorToken]

    var id: String { title }

    static let all: [ColorTokenGroup] = [
        ColorTokenGroup(
            title: "Text",
            note: "Hierarchical shape styles: they keep vibrancy on glass and follow Increase Contrast.",
            tokens: [
                ColorToken("DS.Color.textPrimary", "HierarchicalShapeStyle.primary · label", DS.Color.textPrimary, kind: .text),
                ColorToken("DS.Color.textSecondary", ".secondary · secondaryLabel", DS.Color.textSecondary, kind: .text),
                ColorToken("DS.Color.textTertiary", ".tertiary · tertiaryLabel", DS.Color.textTertiary, kind: .text),
                ColorToken("DS.Color.textQuaternary", ".quaternary · quaternaryLabel", DS.Color.textQuaternary, kind: .text)
            ]
        ),
        ColorTokenGroup(
            title: "Accent & selection",
            tokens: [
                ColorToken("DS.Color.accent", "Color.accentColor · System Settings accent", DS.Color.accent),
                ColorToken("DS.Color.selectionFill", "accentColor @ 14 %", DS.Color.selectionFill),
                ColorToken("DS.Color.selectionText", "TintShapeStyle (.tint)", DS.Color.selectionText, kind: .text)
            ]
        ),
        ColorTokenGroup(
            title: "Surfaces",
            tokens: [
                ColorToken("DS.Color.separator", "NSColor.separatorColor", DS.Color.separator),
                ColorToken("DS.Color.controlBackground", "NSColor.controlBackgroundColor", DS.Color.controlBackground),
                ColorToken("DS.Color.cardFill", "HierarchicalShapeStyle.quinary", DS.Color.cardFill),
                ColorToken("DS.Color.windowBackground", "NSColor.windowBackgroundColor", DS.Color.windowBackground)
            ]
        ),
        ColorTokenGroup(
            title: "Status",
            tokens: [
                ColorToken("DS.Color.success", "Color.green · systemGreen", DS.Color.success),
                ColorToken("DS.Color.warning", "Color.orange · systemOrange", DS.Color.warning),
                ColorToken("DS.Color.error", "Color.red · systemRed", DS.Color.error),
                ColorToken("DS.Color.successFill", "success @ statusFillOpacity (14 %)", DS.Color.successFill),
                ColorToken("DS.Color.warningFill", "warning @ 14 %", DS.Color.warningFill),
                ColorToken("DS.Color.errorFill", "error @ 14 %", DS.Color.errorFill)
            ]
        ),
        ColorTokenGroup(
            title: "glTF roles",
            note: "Fixed meaning-colours: they do not follow the accent.",
            tokens: [
                ColorToken("DS.Color.Role.mesh", "fixed #6E6E73 / #A0A0A6", DS.Color.Role.mesh),
                ColorToken("DS.Color.Role.camera", "fixed #0A84FF / #4CA8FF", DS.Color.Role.camera),
                ColorToken("DS.Color.Role.light", "fixed #F5A623 / #FFC04D", DS.Color.Role.light),
                ColorToken("DS.Color.Role.material", "fixed #A06BD6 / #C29BEC", DS.Color.Role.material),
                ColorToken("DS.Color.Role.animation", "fixed #34C759 / #30D158", DS.Color.Role.animation)
            ]
        ),
        ColorTokenGroup(
            title: "Axes",
            tokens: [
                ColorToken("DS.Color.Axis.x", "fixed sRGB #E2564A", DS.Color.Axis.x),
                ColorToken("DS.Color.Axis.y", "fixed sRGB #34C759", DS.Color.Axis.y),
                ColorToken("DS.Color.Axis.z", "fixed sRGB #0A84FF", DS.Color.Axis.z)
            ]
        ),
        ColorTokenGroup(
            title: "Backdrop & canvas",
            note: "What the canvas paints — the same in either appearance, except the canvas ground.",
            tokens: [
                ColorToken("DS.Color.Backdrop.white", "fixed #FFFFFF", DS.Color.Backdrop.white),
                ColorToken("DS.Color.Backdrop.dark", "fixed #2C2C2E", DS.Color.Backdrop.dark),
                ColorToken("DS.Color.Backdrop.checker", "fixed #DCDCE0", DS.Color.Backdrop.checker),
                ColorToken("DS.Color.Canvas.ground", "fixed #ECEEF1 / #1A1B1D", DS.Color.Canvas.ground),
                ColorToken("DS.Color.Canvas.gradient", "EllipticalGradient over ground", DS.Color.Canvas.gradient)
            ]
        )
    ]
}

private struct ColorSwatch: View {
    let token: ColorToken

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)

        Group {
            switch token.kind {
            case .fill:
                shape.fill(token.style)
                    .frame(width: 96, height: 36)
            case .text:
                HStack(spacing: DS.Spacing.s) {
                    Text("Aa")
                        .font(DS.Font.title)
                    Capsule()
                        .frame(width: 40, height: 6)
                }
                .foregroundStyle(token.style)
                .frame(width: 96, height: 36)
            }
        }
        .padding(DS.Spacing.xs)
        .background(DS.Color.windowBackground, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                .strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline)
        )
        .accessibilityHidden(true)
    }
}
