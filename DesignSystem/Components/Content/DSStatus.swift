import SwiftUI

/// Outcome vocabulary shared by `DSStatusBadge` and `DSDisclosureCard`: one SF Symbol, one system
/// colour and one tinted fill per status, so "valid" looks the same wherever it appears.
public enum DSStatus: Sendable, Hashable, CaseIterable {
    /// Passed / succeeded (glTF validation clean). System green.
    case valid
    /// Something lossy or suspect, still usable. System orange.
    case warning
    /// Failed / invalid. System red.
    case error
    /// Not known yet (validation still running). Neutral secondary, no colour.
    case pending

    /// SF Symbol for the status. Shape differs per status, so it never relies on colour alone.
    public var systemImage: String {
        switch self {
        case .valid: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .pending: "ellipsis.circle"
        }
    }

    /// Glyph colour.
    public var tint: AnyShapeStyle {
        switch self {
        case .valid: AnyShapeStyle(DS.Color.success)
        case .warning: AnyShapeStyle(DS.Color.warning)
        case .error: AnyShapeStyle(DS.Color.error)
        case .pending: AnyShapeStyle(DS.Color.textSecondary)
        }
    }

    /// Background wash behind a badge or card.
    public var fill: AnyShapeStyle {
        switch self {
        case .valid: AnyShapeStyle(DS.Color.successFill)
        case .warning: AnyShapeStyle(DS.Color.warningFill)
        case .error: AnyShapeStyle(DS.Color.errorFill)
        case .pending: AnyShapeStyle(DS.Color.cardFill)
        }
    }
}
