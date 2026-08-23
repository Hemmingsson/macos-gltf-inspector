import SwiftUI

/// Convert losses next to Khronos validation — “not rendered as authored”.
public struct ConvertProblemsSection: View {
    public var problems: ConvertProblemList
    @State private var isExpanded: Bool = false

    public var body: some View {
        if !problems.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Not rendered as authored")

            StatusWarningCard(
                summaryTitle: summaryTitle,
                rows: problems.entries.map {
                    StatusWarningCard.Row(id: $0.id, message: $0.title)
                },
                isExpanded: $isExpanded,
                collapseAccessibilityHint: "Collapse problems",
                expandAccessibilityHint: "Expand problems"
            )
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .onAppear {
            if problems.errorCount > 0 { isExpanded = true }
        }
    }

    private var summaryTitle: String {
        let errors = problems.errorCount
        let warnings = problems.warningCount
        if errors > 0 && warnings > 0 {
            return "\(errors) errors · \(warnings) warnings"
        }
        if errors > 0 {
            return errors == 1 ? "1 error" : "\(errors) errors"
        }
        return warnings == 1 ? "1 warning" : "\(warnings) warnings"
    }
}

// MARK: - Previews

#Preview("with issues", traits: .fixedLayout(width: Theme.sidebarWidth, height: 180)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 180) {
        ConvertProblemsSection(problems: ValidationFixtures.convertProblems)
    }
}
