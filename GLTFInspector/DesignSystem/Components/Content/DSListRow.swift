import SwiftUI

/// An outliner / list row: leading icon, title (middle-truncated, so "Cube.001" keeps its suffix),
/// optional subtitle, and a trailing accessory (a count, say).
///
/// Built for a native `List(selection:)`: the row draws **no** selection of its own — the list's
/// highlight and emphasised text styles apply because every colour is hierarchical. For a custom
/// row that cannot use native selection, pass `isSelected: true`: the row paints
/// `DS.Color.selectionFill` (outset behind it, so layout does not shift) and switches the title to
/// `DS.Color.selectionText`.
struct DSListRow<Icon: View, Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let isSelected: Bool
    private let icon: Icon
    private let accessory: Accessory

    init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.icon = icon()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(DS.Font.body)
                    .foregroundStyle(titleStyle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.subheadline)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: DS.Spacing.m)
            accessory
        }
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
                    .fill(DS.Color.selectionFill)
                    .padding(.horizontal, -DS.Spacing.s)
                    .padding(.vertical, -DS.Spacing.xs)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var titleStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(DS.Color.selectionText) : AnyShapeStyle(DS.Color.textPrimary)
    }
}

extension DSListRow where Accessory == EmptyView {
    /// Row without a trailing accessory.
    init(
        _ title: String,
        subtitle: String? = nil,
        isSelected: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) {
        self.init(title, subtitle: subtitle, isSelected: isSelected, icon: icon) {
            EmptyView()
        }
    }
}

extension DSListRow where Icon == DSTypeIcon {
    /// Row whose icon is the glTF type glyph; the glyph follows `isSelected`.
    init(
        _ title: String,
        subtitle: String? = nil,
        role: NodeKind,
        isSelected: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.init(
            title,
            subtitle: subtitle,
            isSelected: isSelected,
            icon: { DSTypeIcon(role, isSelected: isSelected) },
            accessory: accessory
        )
    }
}

extension DSListRow where Icon == DSTypeIcon, Accessory == EmptyView {
    /// Type-glyph row without an accessory.
    init(
        _ title: String,
        subtitle: String? = nil,
        role: NodeKind,
        isSelected: Bool = false
    ) {
        self.init(title, subtitle: subtitle, role: role, isSelected: isSelected) {
            EmptyView()
        }
    }
}
