import SwiftUI

/// Validator findings about the selected node or material, shown last, under its facts: what the
/// file says comes first, what is wrong with it after.
///
/// The file-wide list in the sidebar says *that* something is off; this says *where*. Faults come
/// first, notes (infos and hints) stay neutral. Nothing renders when the selection has no issues.
struct IssuesSection: View {
    var issues: [ValidationResult.Issue]
    var digests: ValidationDigestStore

    var body: some View {
        if !issues.isEmpty {
            let groups = ValidationIssueGrouping.group(issues)
            let counts = issueSummary(
                errors: issues.filter { $0.severity == .error }.count,
                warnings: issues.filter { $0.severity == .warning }.count,
                notes: issues.filter { $0.severity == .info || $0.severity == .hint }.count
            )
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                // One raw issue needs no count line; an AI sentence or a multi-finding list does.
                if let headline = digests.modelHeadline(for: issues),
                   ValidationIssueGrouping.headlineAddsValue(headline, groups: groups) {
                    Text(headline)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: "Issue summary: \(headline)"))
                } else if groups.count > 1 || groups.contains(where: { $0.count > 1 }) {
                    Text(counts)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(verbatim: "Issue summary: \(counts)"))
                }
                ForEach(groups) { group in
                    InlineGroupedIssue(group: group)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xs)
            .padding(.bottom, DS.Spacing.m)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Validation issues")
            .task(id: ValidationIssueGrouping.digestKey(issues)) {
                digests.request(issues, scope: .selection)
            }
        }
    }
}

/// One grouped finding on the status wash — shared block layout, per-row chrome.
private struct InlineGroupedIssue: View {
    var group: GroupedValidationIssue

    var body: some View {
        GroupedIssueBlock(group: group, detailForegroundStyle: .primary)
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.l)
            .padding(.vertical, DS.Spacing.m)
            .background(
                group.severity.dsStatus.fill,
                in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(verbatim: "\(Self.spokenPrefix(group.severity.dsStatus)) \(GroupedIssueBlock.accessibilityText(for: group))")
            )
    }

    private static func spokenPrefix(_ status: DSStatus) -> String {
        switch status {
        case .error: "Error:"
        case .warning: "Warning:"
        case .note: "Note:"
        case .valid, .pending: ""
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
