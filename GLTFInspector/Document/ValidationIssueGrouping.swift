import Foundation

/// Identical validator findings collapsed to one row with a count.
struct GroupedValidationIssue: Identifiable, Hashable, Sendable {
    var severity: ValidationResult.Issue.Severity
    var code: String
    var message: String
    var count: Int

    var id: String { "\(severity.rawValue)|\(code)|\(message)" }

    /// UX skim for this Khronos code (or the raw message when unknown).
    var skim: String { ValidationIssueCopy.skim(code: code, message: message) }

    /// One-line skim with ×N when the finding repeats.
    var summaryLine: String {
        let head = skim
        return count > 1 ? "\(head) (×\(count))" : head
    }

    /// Full validator message — never includes a count suffix.
    var detailText: String { message }

    /// True when the Khronos message adds detail beyond the skim (second sentence, etc.).
    var showsDetailBelowSkim: Bool {
        ValidationIssueCopy.detailAddsBeyondSkim(skim: skim, message: message, code: code)
    }
}

/// Deterministic grouping of validation findings.
enum ValidationIssueGrouping {
    /// Collapses identical `(severity, code, message)` tuples; faults first, stable by message.
    static func group(_ issues: [ValidationResult.Issue]) -> [GroupedValidationIssue] {
        var order: [String] = []
        var counts: [String: (severity: ValidationResult.Issue.Severity, code: String, message: String, count: Int)] = [:]
        for issue in issues {
            let key = "\(issue.severity.rawValue)|\(issue.code)|\(issue.message)"
            if var existing = counts[key] {
                existing.count += 1
                counts[key] = existing
            } else {
                order.append(key)
                counts[key] = (issue.severity, issue.code, issue.message, 1)
            }
        }
        return order.compactMap { key -> GroupedValidationIssue? in
            guard let entry = counts[key] else { return nil }
            return GroupedValidationIssue(
                severity: entry.severity,
                code: entry.code,
                message: entry.message,
                count: entry.count
            )
        }
        .sorted {
            if $0.severity.rank != $1.severity.rank { return $0.severity.rank < $1.severity.rank }
            return $0.message < $1.message
        }
    }
}