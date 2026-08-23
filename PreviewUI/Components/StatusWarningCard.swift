import SwiftUI

/// Expandable amber warning card — validation issues and convert problems.
public struct StatusWarningCard: View {
    public struct Row: Identifiable, Sendable, Hashable {
        public var id: String
        public var message: String

        public init(id: String, message: String) {
            self.id = id
            self.message = message
        }
    }

    public var summaryTitle: String
    public var rows: [Row]
    @Binding public var isExpanded: Bool
    public var collapseAccessibilityHint: String
    public var expandAccessibilityHint: String

    public init(
        summaryTitle: String,
        rows: [Row],
        isExpanded: Binding<Bool>,
        collapseAccessibilityHint: String = "Collapse warnings",
        expandAccessibilityHint: String = "Expand warnings"
    ) {
        self.summaryTitle = summaryTitle
        self.rows = rows
        self._isExpanded = isExpanded
        self.collapseAccessibilityHint = collapseAccessibilityHint
        self.expandAccessibilityHint = expandAccessibilityHint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Self.warnStroke)
                    Text(summaryTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Self.warnText)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Self.warnText.opacity(0.7))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryTitle)
            .accessibilityHint(isExpanded ? collapseAccessibilityHint : expandAccessibilityHint)

            if isExpanded {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(Self.warnStroke)
                            .padding(.top, 1)
                        Text(row.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        if index < rows.count - 1 {
                            Theme.hair.frame(height: Theme.hairlineWidth)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Self.warnFill)
        )
    }

    public static let warnFill = Color.dynamic(
        light: .init(srgbRed: 245 / 255, green: 166 / 255, blue: 35 / 255, alpha: 0.10),
        dark: .init(srgbRed: 245 / 255, green: 166 / 255, blue: 35 / 255, alpha: 0.18)
    )
    public static let warnStroke = Color.dynamic(light: 0xD6902A, dark: 0xFFC04D)
    public static let warnText = Color.dynamic(light: 0xA86C1A, dark: 0xFFC04D)
}

// MARK: - Previews

private enum StatusWarningCardPreviewFixtures {
    static let rows = [
        StatusWarningCard.Row(
            id: "accessor-alignment",
            message: "Accessor min length must be a multiple of component size"
        ),
        StatusWarningCard.Row(
            id: "unused-extension",
            message: "Unused extension KHR_materials_unlit"
        ),
    ]
}

#Preview("collapsed", traits: .fixedLayout(width: Theme.inspectorWidth, height: 120)) {
    PreviewCanvas(width: Theme.inspectorWidth, height: 120) {
        StatusWarningCard(
            summaryTitle: "2 warnings",
            rows: StatusWarningCardPreviewFixtures.rows,
            isExpanded: .constant(false)
        )
    }
}

#Preview("expanded", traits: .fixedLayout(width: Theme.inspectorWidth, height: 220)) {
    PreviewCanvas(width: Theme.inspectorWidth, height: 220) {
        StatusWarningCard(
            summaryTitle: "2 warnings",
            rows: StatusWarningCardPreviewFixtures.rows,
            isExpanded: .constant(true)
        )
    }
}
