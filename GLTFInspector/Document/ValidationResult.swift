import Foundation
import GLTFCore

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
        /// Outliner rows this issue is about, resolved from `pointer`. An issue with none (an
        /// accessor, a buffer view) shows only in the file-wide list.
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

extension ValidationResult {
    /// The validator's outcome for `document`, each issue resolved to the outliner rows it is
    /// about. Nil `state` means the run has not finished.
    init(_ state: GLTFValidationState?, document: GLTFDocument) {
        switch state {
        case nil:
            self.init(status: .pending)
        case .success(let report):
            self.init(issues: report.messages.map { message in
                Issue(
                    severity: Issue.Severity(validatorSeverity: message.severity),
                    message: message.message,
                    pointer: message.pointer,
                    subjects: GLTFIssueResolver.subjects(forPointer: message.pointer, in: document).compactMap { subject in
                        switch subject {
                        case .node(let index): document.id(ofNode: index)
                        case .material(let index): NodeID(kind: .material, index: index)
                        case .scene(let index): NodeID(kind: .scene, index: index)
                        case .skin(let index): NodeID(kind: .skin, index: index)
                        case .animation(let index): NodeID(kind: .animation, index: index)
                        }
                    }
                )
            })
        case .failed(let message), .skipped(let message):
            self.init(issues: [Issue(severity: .warning, message: message)], status: .unavailable)
        }
    }
}

extension ValidationResult.Issue.Severity {
    /// glTF-Validator severities: 0 error, 1 warning, 2 info, 3 hint.
    init(validatorSeverity: Int) {
        self = switch validatorSeverity {
        case 0: .error
        case 1: .warning
        case 2: .info
        default: .hint
        }
    }
}
