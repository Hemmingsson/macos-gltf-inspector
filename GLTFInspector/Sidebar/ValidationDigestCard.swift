import SwiftUI

/// Status card for validation findings: short summary lines with ×N, full text on each item.
/// Used in the sidebar footer (and nowhere else) so one place owns the list.
struct ValidationDigestCard: View {
    var title: String
    var status: DSStatus
    var groups: [GroupedValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(groups) { group in
                GroupedIssueBlock(group: group)
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.fill, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "Validation: \(title)"))
    }
}

/// One grouped finding: UX skim when it differs from Khronos detail; otherwise a single line.
struct GroupedIssueBlock: View {
    var group: GroupedValidationIssue
    /// Inspector rows keep detail at primary; the sidebar card uses secondary under a skim line.
    var detailForegroundStyle: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            if group.showsDetailBelowSkim {
                SummarySkimLine(group: group)
            }
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Image(systemName: group.severity.dsStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(group.severity.dsStatus.tint)
                    .accessibilityHidden(true)
                Text(group.showsDetailBelowSkim ? group.detailText : group.summaryLine)
                    .font(.callout)
                    .foregroundStyle(group.showsDetailBelowSkim ? detailForegroundStyle : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: Self.accessibilityText(for: group)))
    }

    static func accessibilityText(for group: GroupedValidationIssue) -> String {
        if group.showsDetailBelowSkim {
            return "\(group.summaryLine) \(group.detailText)"
        }
        return group.summaryLine
    }
}

/// One-line skim that keeps `(×N)` visible when the head truncates.
private struct SummarySkimLine: View {
    var group: GroupedValidationIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Text(group.skim)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if group.count > 1 {
                Text("(×\(group.count))")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .layoutPriority(1)
                    .fixedSize()
            }
        }
    }
}