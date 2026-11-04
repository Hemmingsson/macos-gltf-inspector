import Foundation

/// glTF-validator output, surfaced verbatim — "is the file wrong, or are we?".
struct ValidationResult: Sendable, Hashable {
    struct Issue: Sendable, Hashable, Identifiable {
        enum Severity: String, Sendable, Hashable, Codable, CaseIterable {
            case error
            case warning
            case info
            case hint
        }

        var severity: Severity
        var message: String
        /// glTF JSON pointer the validator blamed, when it gave one.
        var pointer: String?
        /// Outliner rows this issue is about, resolved from `pointer` by the engine adapter. An
        /// issue with none (an accessor, a buffer view) shows only in the file-wide list.
        var subjects: [NodeID]

        var id: String { "\(severity.rawValue)|\(pointer ?? "")|\(message)" }

        init(
            severity: Severity,
            message: String,
            pointer: String? = nil,
            subjects: [NodeID] = []
        ) {
            self.severity = severity
            self.message = message
            self.pointer = pointer
            self.subjects = subjects
        }
    }

    var issues: [Issue]
    /// Pending means the Khronos run has not finished; unavailable is a hard skip/fail.
    var status: Status

    enum Status: String, Sendable, Hashable {
        case pending
        case ready
        case unavailable
    }

    init(
        issues: [Issue] = [],
        status: Status = .ready
    ) {
        self.issues = issues
        self.status = status
    }

    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    /// Infos and hints: worth reading, not faults, so they are counted apart from warnings.
    var noteCount: Int { issues.filter { $0.severity == .info || $0.severity == .hint }.count }
    /// Green “Valid” only after a successful run with no errors or warnings.
    var isClean: Bool { status == .ready && errorCount == 0 && warningCount == 0 }

    /// Issues about `id`, most severe first (the order the file-wide list keeps within a severity).
    func issues(for id: NodeID) -> [Issue] {
        issues.filter { $0.subjects.contains(id) }.sorted { $0.severity.rank < $1.severity.rank }
    }

    /// The most severe issue about `id`, for a badge on its outliner row.
    func worstSeverity(for id: NodeID) -> Issue.Severity? {
        issues(for: id).first?.severity
    }
}

extension ValidationResult.Issue.Severity {
    /// 0 is worst. Sorts a mixed list so faults come before notes.
    var rank: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .info: 2
        case .hint: 3
        }
    }
}
