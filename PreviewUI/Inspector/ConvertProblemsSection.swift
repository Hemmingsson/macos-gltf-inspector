import DesignSystem
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
            InspectorSectionHeader("Not rendered as authored", top: DS.Spacing.m)

            DSDisclosureCard(
                summaryTitle,
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

#Preview("with issues", traits: .fixedLayout(width: 248, height: 180)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 180) {
        ConvertProblemsSection(problems: ValidationFixtures.convertProblems)
    }
}
