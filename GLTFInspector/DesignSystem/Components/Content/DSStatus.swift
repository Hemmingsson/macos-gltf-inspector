import SwiftUI

/// Outcome vocabulary shared by `DSStatusBadge` and `DSDisclosureCard`: one SF Symbol, one system
/// colour and one tinted fill per status, so "valid" looks the same wherever it appears.
enum DSStatus: Sendable, Hashable, CaseIterable {
    /// Passed / succeeded (glTF validation clean). System green.
    case valid
    /// Something lossy or suspect, still usable. System orange.
    case warning
    /// Failed / invalid. System red.
    case error
    /// Not known yet (validation still running). Neutral secondary, no colour.
    case pending
    /// Worth knowing, not a fault (a validator info or hint). Neutral secondary, no colour.
    case note

    /// SF Symbol for the status. Shape differs per status, so it never relies on colour alone.
    var systemImage: String {
        switch self {
        case .valid: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .pending: "ellipsis.circle"
        case .note: "info.circle"
        }
    }

    /// Glyph colour.
    var tint: AnyShapeStyle {
        switch self {
        case .valid: AnyShapeStyle(Color.green)
        case .warning: AnyShapeStyle(Color.orange)
        case .error: AnyShapeStyle(Color.red)
        case .pending, .note: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        }
    }

    /// Background wash behind a badge or card.
    var fill: AnyShapeStyle {
        switch self {
        case .valid: AnyShapeStyle(Color.green.opacity(0.14))
        case .warning: AnyShapeStyle(Color.orange.opacity(0.14))
        case .error: AnyShapeStyle(Color.red.opacity(0.14))
        case .pending, .note: AnyShapeStyle(HierarchicalShapeStyle.quinary)
        }
    }
}
