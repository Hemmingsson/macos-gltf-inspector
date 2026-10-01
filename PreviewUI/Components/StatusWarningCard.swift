import DesignSystem
import SwiftUI

/// Expandable warning card — a thin `DSDisclosureCard` wrapper so existing callers keep a
/// `Row` vocabulary.
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
    public var status: DSStatus
    public var collapseAccessibilityHint: String
    public var expandAccessibilityHint: String

    public init(
        summaryTitle: String,
        rows: [Row],
        isExpanded: Binding<Bool>,
        status: DSStatus = .warning,
        collapseAccessibilityHint: String = "Collapse warnings",
        expandAccessibilityHint: String = "Expand warnings"
    ) {
        self.summaryTitle = summaryTitle
        self.rows = rows
        self._isExpanded = isExpanded
        self.status = status
        self.collapseAccessibilityHint = collapseAccessibilityHint
        self.expandAccessibilityHint = expandAccessibilityHint
    }

    public var body: some View {
        DSDisclosureCard(
            summaryTitle,
            status: status,
            isExpanded: $isExpanded,
            messages: rows.map { DSDisclosureMessage(id: $0.id, text: $0.message) }
        )
        .accessibilityHint(isExpanded ? collapseAccessibilityHint : expandAccessibilityHint)
    }
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

#Preview("collapsed", traits: .fixedLayout(width: 288, height: 120)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 120) {
        StatusWarningCard(
            summaryTitle: "2 warnings",
            rows: StatusWarningCardPreviewFixtures.rows,
            isExpanded: .constant(false)
        )
        .padding(DS.Spacing.l)
    }
}

#Preview("expanded", traits: .fixedLayout(width: 288, height: 220)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 220) {
        StatusWarningCard(
            summaryTitle: "2 warnings",
            rows: StatusWarningCardPreviewFixtures.rows,
            isExpanded: .constant(true)
        )
        .padding(DS.Spacing.l)
    }
}
