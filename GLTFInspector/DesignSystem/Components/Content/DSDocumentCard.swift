import SwiftUI

/// The document's identity card at the top of the sidebar: file icon in the accent colour, file
/// name, scene subtitle, and an accessory slot (the material-variant `DSMenuPicker`).
///
/// The window has no title band, so this card is where the file names itself. The icon uses the
/// accent — not a type tint — because it stands for the document, not an outliner row. The title
/// truncates in the middle so the extension stays visible. The accessory sits below the title row
/// at the card's full width, so a long variant name never squeezes the file name.
///
/// With an `action`, the title row is a button (it selects the whole document); `isSelected` then
/// draws the card with the accent selection fill and an accent hairline.
///
/// Opaque `DS.Color.controlBackground` ground with a `DS.Color.separator` hairline at
/// `DS.Radius.large`. The icon and texts are one accessibility element; the accessory stays its
/// own control.
struct DSDocumentCard<Accessory: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let isSelected: Bool
    private let action: (() -> Void)?
    private let accessory: Accessory

    /// - Parameters:
    ///   - title: File name.
    ///   - subtitle: Scene name; `nil` collapses the line rather than printing a placeholder.
    ///   - systemImage: Document glyph. Defaults to `cube`.
    ///   - isSelected: The whole document is selected.
    ///   - action: Click on the title row; `nil` leaves the card static.
    ///   - accessory: Extra control under the title row.
    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String = "cube",
        isSelected: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.large, style: .continuous)

        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            if let action {
                Button(action: action) { titleRow }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            } else {
                titleRow
            }

            accessory
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background {
            ZStack {
                shape.fill(DS.Color.controlBackground)
                if isSelected { shape.fill(Color.accentColor.opacity(0.14)) }
            }
        }
        .overlay(
            shape.strokeBorder(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(DS.Color.separator),
                lineWidth: DS.Metrics.hairline
            )
        )
    }

    private var titleRow: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: systemImage)
                .font(.body)
                .imageScale(.large)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension DSDocumentCard where Accessory == EmptyView {
    /// Card without an accessory.
    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String = "cube",
        isSelected: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title,
            subtitle: subtitle,
            systemImage: systemImage,
            isSelected: isSelected,
            action: action
        ) { EmptyView() }
    }
}
