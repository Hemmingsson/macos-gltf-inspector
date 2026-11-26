import SwiftUI

/// glTF-validator badge. Clean fixtures stay a quiet green card; faults use the digest card.
/// Infos/hints stay out of this footer — they only surface in the inspector for a selection.
struct ValidationSection: View {
    var validation: ValidationResult
    var digests: ValidationDigestStore

    /// Errors and warnings only — notes belong on the selected outliner row’s inspector.
    private var faultIssues: [ValidationResult.Issue] {
        validation.issues.filter { $0.severity == .error || $0.severity == .warning }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if validation.status != .ready || !validation.isClean {
                InspectorSectionHeader("Validation", top: DS.Spacing.m)
            }

            Group {
                if validation.status == .pending {
                    DSStatusBadge("Checking validation…", status: .pending)
                } else if validation.isClean {
                    DSStatusBadge("Valid glTF 2.0", status: .valid)
                } else {
                    digestCard(status: validation.errorCount > 0 ? .error : .warning)
                }
            }
            .padding(.horizontal, DS.Spacing.paneInset)
            .padding(.top, validation.isClean && validation.status == .ready ? DS.Spacing.xs : DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.xs)
        }
    }

    private func digestCard(status: DSStatus) -> some View {
        let counts = issueSummary(
            errors: validation.errorCount,
            warnings: validation.warningCount
        )
        let groups = ValidationIssueGrouping.group(faultIssues)
        return ValidationDigestCard(
            title: digests.cardTitle(for: faultIssues, groups: groups, fallback: counts),
            status: status,
            groups: groups
        )
    }
}
