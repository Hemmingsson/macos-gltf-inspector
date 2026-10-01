import DesignSystem
import SwiftUI

/// A catalog page: title, symbol, one-line purpose, then the page's rows in a scroll view.
struct CatalogPageView<Content: View>: View {
    let page: CatalogPage
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(page.title)
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(page.symbol)
                        .font(DS.Font.callout.monospaced())
                        .foregroundStyle(DS.Color.textSecondary)
                        .textSelection(.enabled)
                    Text(page.purpose)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(DS.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Color.windowBackground)
    }
}

/// A group of state rows under an optional section header.
struct StateGroup<Content: View>: View {
    var title: String?
    var note: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.l) {
            if let title {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    DSSectionHeader(title)
                    if let note {
                        Text(note)
                            .font(DS.Font.callout)
                            .foregroundStyle(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content()
        }
    }
}

/// One state of a component, rendered over the toolbar-selected backdrop.
///
/// `content` is evaluated in the cell, so any `Live` state inside is per cell.
struct StateRow<Content: View>: View {
    let title: String
    var note: String?
    var alignment: Alignment = .center
    var minHeight: CGFloat = 88
    @ViewBuilder var content: () -> Content

    @Environment(\.catalogBackdrop) private var backdrop

    init(
        _ title: String,
        note: String? = nil,
        alignment: Alignment = .center,
        minHeight: CGFloat = 88,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.note = note
        self.alignment = alignment
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Text(title)
                    .font(DS.Font.bodyEmphasized)
                    .foregroundStyle(DS.Color.textPrimary)
                if let note {
                    Text(note)
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            BackdropCell(backdrop: backdrop, alignment: alignment, minHeight: minHeight) {
                content()
            }
        }
    }
}

/// One component over the selected backdrop. No caption chip — the toolbar names the ground.
private struct BackdropCell<Content: View>: View {
    let backdrop: CatalogBackdrop
    let alignment: Alignment
    let minHeight: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)

        content()
            .padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: alignment)
            .background { backdrop.ground }
            .clipShape(shape)
            .overlay(shape.strokeBorder(DS.Color.separator, lineWidth: DS.Metrics.hairline))
    }
}

/// Holds a value in `@State` for an interactive state or a mock object. Initial value only —
/// assigned through `_value` in `init`, never mutated there.
struct Live<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }

    var body: some View {
        content($value)
    }
}

/// Stand-in for the system popover so popover bodies can be judged inline over each backdrop.
/// A real popover draws its own glass; open the live chip to compare.
struct PopoverStandIn<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .glassEffect(DS.Glass.hud, in: RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous))
    }
}

/// A token row label: monospaced token name over its resolved system role.
struct TokenLabel: View {
    let name: String
    let role: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(name)
                .font(DS.Font.callout.monospaced())
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
            Text(role)
                .font(DS.Font.subheadline)
                .foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
