import Foundation

/// glTF-validator output, surfaced verbatim — "is the file wrong, or are we?".
public struct ValidationResult: Sendable, Hashable {
    public struct Issue: Sendable, Hashable, Identifiable {
        public enum Severity: String, Sendable, Hashable, Codable, CaseIterable {
            case error
            case warning
            case info
            case hint
        }

        public var severity: Severity
        public var message: String
        /// glTF JSON pointer the validator blamed, when it gave one.
        public var pointer: String?

        public var id: String { "\(severity.rawValue)|\(pointer ?? "")|\(message)" }

        public init(severity: Severity, message: String, pointer: String? = nil) {
            self.severity = severity
            self.message = message
            self.pointer = pointer
        }
    }

    public var issues: [Issue]
    /// Pending means the Khronos run has not finished; unavailable is a hard skip/fail.
    public var status: Status

    public enum Status: String, Sendable, Hashable {
        case pending
        case ready
        case unavailable
    }

    public init(
        issues: [Issue] = [],
        status: Status = .ready
    ) {
        self.issues = issues
        self.status = status
    }

    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    /// Green “Valid” only after a successful run with no errors or warnings.
    public var isClean: Bool { status == .ready && errorCount == 0 && warningCount == 0 }
}
