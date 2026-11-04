import DesignSystem

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
