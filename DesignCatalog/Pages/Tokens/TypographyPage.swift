import AppKit
import DesignSystem
import SwiftUI

/// The `DS.Font` ramp: token name, the text style it maps to (with today's resolved point size),
/// and a sample line.
struct TypographyPage: View {
    private static let sample = "Cube.001 · 12 triangles · 0.50 × 1.25 m"

    var body: some View {
        CatalogPageView(page: .typography) {
            StateGroup(
                title: "Type ramp",
                note: "Point sizes are what AppKit resolves for the text style right now (NSFont.preferredFont)."
            ) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Spacing.xl, verticalSpacing: DS.Spacing.l) {
                    ForEach(FontToken.all) { token in
                        GridRow {
                            TokenLabel(name: token.name, role: token.role)
                                .frame(width: 280, alignment: .leading)
                            token.sample(Self.sample)
                                .foregroundStyle(DS.Color.textPrimary)
                                .lineLimit(2)
                        }
                        Divider()
                    }
                }
            }

            StateGroup(title: "Hierarchy on one ground") {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    Text("Cube.glb").font(DS.Font.title).foregroundStyle(DS.Color.textPrimary)
                    Text("Scene · 3 nodes").font(DS.Font.subheadline).foregroundStyle(DS.Color.textSecondary)
                    Text("Geometry").dsSectionHeader().foregroundStyle(DS.Color.textSecondary)
                    HStack {
                        Text("Triangles").font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        Spacer()
                        Text("12").font(DS.Font.value).foregroundStyle(DS.Color.textPrimary)
                    }
                    .frame(width: 260)
                    Text("1 UV set").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    Text("X  Y  Z").font(DS.Font.micro).foregroundStyle(DS.Color.textTertiary)
                }
            }
        }
    }
}

private struct FontToken: Identifiable {
    let name: String
    let textStyle: String
    let nsStyle: NSFont.TextStyle
    let font: Font
    var isSectionHeader = false

    var id: String { name }

    var role: String {
        let size = NSFont.preferredFont(forTextStyle: nsStyle).pointSize
        return "\(textStyle) · \(Double(size).formatted(.number.precision(.fractionLength(0...1)))) pt"
    }

    @ViewBuilder
    func sample(_ text: String) -> some View {
        if isSectionHeader {
            Text(text).dsSectionHeader()
        } else {
            Text(text).font(font)
        }
    }

    static let all: [FontToken] = [
        FontToken(name: "DS.Font.title", textStyle: "Font.title3 semibold", nsStyle: .title3, font: DS.Font.title),
        FontToken(name: "DS.Font.body", textStyle: "Font.body", nsStyle: .body, font: DS.Font.body),
        FontToken(name: "DS.Font.bodyEmphasized", textStyle: "Font.body semibold", nsStyle: .body, font: DS.Font.bodyEmphasized),
        FontToken(name: "DS.Font.callout", textStyle: "Font.callout", nsStyle: .callout, font: DS.Font.callout),
        FontToken(name: "DS.Font.value", textStyle: "Font.callout monospacedDigit", nsStyle: .callout, font: DS.Font.value),
        FontToken(name: "DS.Font.subheadline", textStyle: "Font.subheadline", nsStyle: .subheadline, font: DS.Font.subheadline),
        FontToken(
            name: "DS.Font.sectionHeader",
            textStyle: "Font.subheadline semibold · uppercase · tracking 0.5",
            nsStyle: .subheadline,
            font: DS.Font.sectionHeader,
            isSectionHeader: true
        ),
        FontToken(name: "DS.Font.caption", textStyle: "Font.caption", nsStyle: .caption1, font: DS.Font.caption),
        FontToken(name: "DS.Font.micro", textStyle: "Font.caption2", nsStyle: .caption2, font: DS.Font.micro)
    ]
}
