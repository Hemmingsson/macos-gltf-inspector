import Foundation

/// The inspector's File section.
public struct Stats: Sendable, Hashable {
    public var triangleCount: Int
    public var meshCount: Int
    public var materialCount: Int
    public var textureCount: Int
    /// Largest texture edge in pixels ("max 2048²"). Nil when there are no textures.
    public var maxTextureDimension: Int?
    public var animationCount: Int
    public var fileSizeBytes: Int64?

    public init(
        triangleCount: Int = 0,
        meshCount: Int = 0,
        materialCount: Int = 0,
        textureCount: Int = 0,
        maxTextureDimension: Int? = nil,
        animationCount: Int = 0,
        fileSizeBytes: Int64? = nil
    ) {
        self.triangleCount = triangleCount
        self.meshCount = meshCount
        self.materialCount = materialCount
        self.textureCount = textureCount
        self.maxTextureDimension = maxTextureDimension
        self.animationCount = animationCount
        self.fileSizeBytes = fileSizeBytes
    }
}

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
    /// "glTF 2.0" — shown next to the clean badge.
    public var formatLabel: String
    /// Pending means the Khronos run has not finished; unavailable is a hard skip/fail.
    public var status: Status

    public enum Status: String, Sendable, Hashable {
        case pending
        case ready
        case unavailable
    }

    public init(
        issues: [Issue] = [],
        formatLabel: String = "glTF 2.0",
        status: Status = .ready
    ) {
        self.issues = issues
        self.formatLabel = formatLabel
        self.status = status
    }

    public var errorCount: Int { issues.filter { $0.severity == .error }.count }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count }
    /// Green “Valid” only after a successful run with no errors or warnings.
    public var isClean: Bool { status == .ready && errorCount == 0 && warningCount == 0 }
}

/// "What our pipeline did" — every silent change we made on import.
public struct PipelineReport: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable {
            /// Conversion / dequant steps — “we did work”.
            case conversion
            /// Status line (file lights / studio IBL).
            case lighting
        }

        public var kind: Kind
        public var title: String
        public var detail: String?

        public var id: String { detail.map { "\(title)|\($0)" } ?? title }

        public init(kind: Kind = .conversion, title: String, detail: String? = nil) {
            self.kind = kind
            self.title = title
            self.detail = detail
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
}

/// Convert losses — “not rendered as authored”. Separate from Khronos validation.
public struct ConvertProblemList: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, Identifiable {
        public enum Severity: String, Sendable, Hashable {
            case error
            case warning
        }

        public var severity: Severity
        public var title: String
        public var code: String

        public var id: String { "\(code)|\(severity.rawValue)|\(title)" }

        public init(severity: Severity, title: String, code: String) {
            self.severity = severity
            self.title = title
            self.code = code
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var errorCount: Int { entries.filter { $0.severity == .error }.count }
    public var warningCount: Int { entries.filter { $0.severity == .warning }.count }
}
