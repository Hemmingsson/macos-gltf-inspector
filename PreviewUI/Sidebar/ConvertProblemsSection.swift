import DesignSystem
import SwiftUI

/// Convert losses next to Khronos validation — “not rendered as authored”.
struct ConvertProblemsSection: View {
    var problems: ConvertProblemList
    @State private var isExpanded: Bool = false

    var body: some View {
        if !problems.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader("Not rendered as authored", top: DS.Spacing.m)

            DSDisclosureCard(
                issueSummary(errors: problems.errorCount, warnings: problems.warningCount),
                status: problems.errorCount > 0 ? .error : .warning,
                isExpanded: $isExpanded,
                messages: problems.entries.map {
                    DSDisclosureMessage(id: $0.id, text: $0.title)
                }
            )
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.xs)
        }
        .onAppear {
            if problems.errorCount > 0 { isExpanded = true }
        }
    }
}

// MARK: - Previews

#Preview("with issues", traits: .fixedLayout(width: 248, height: 180)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 180) {
        ConvertProblemsSection(problems: ValidationFixtures.convertProblems)
    }
}
