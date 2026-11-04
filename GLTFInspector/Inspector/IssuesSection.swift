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

extension ValidationResult.Issue.Severity {
    /// How the UI draws this severity: faults in colour, infos and hints as neutral notes.
    var dsStatus: DSStatus {
        switch self {
        case .error: .error
        case .warning: .warning
        case .info, .hint: .note
        }
    }
}

/// "1 error · 2 warnings · 3 notes" — only the counts that are non-zero.
func issueSummary(errors: Int, warnings: Int, notes: Int = 0) -> String {
    var parts: [String] = []
    if errors > 0 { parts.append(errors == 1 ? "1 error" : "\(errors) errors") }
    if warnings > 0 { parts.append(warnings == 1 ? "1 warning" : "\(warnings) warnings") }
    if notes > 0 { parts.append(notes == 1 ? "1 note" : "\(notes) notes") }
    return parts.isEmpty ? "No issues" : parts.joined(separator: " · ")
}
