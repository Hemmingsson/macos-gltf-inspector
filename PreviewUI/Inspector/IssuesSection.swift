import DesignSystem
import SwiftUI

/// Validator findings about the selected node or material, shown above its facts.
///
/// The file-wide list in the sidebar says *that* something is off; this says *where*. Faults come
/// first, notes (infos and hints) stay neutral. Nothing renders when the selection has no issues.
struct IssuesSection: View {
    var issues: [ValidationResult.Issue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                ForEach(issues) { issue in
                    DSInlineIssue(issue.message, status: issue.severity.dsStatus)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.m)
            .padding(.bottom, DS.Spacing.xs)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Validation issues")
        }
    }
}

// MARK: - Previews

#Preview("issues", traits: .fixedLayout(width: DS.Metrics.inspectorWidth, height: 320)) {
    PreviewCanvas(width: DS.Metrics.inspectorWidth, height: 320) {
        IssuesSection(issues: ValidationFixtures.materialIssues)
    }
}
