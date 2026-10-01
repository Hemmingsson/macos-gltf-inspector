import Foundation

/// Which renderer draws the model (`settings.preview.renderer`).
///
/// Settings ▸ Preview ▸ Renderer writes it into the App Group suite; the document window, Quick
/// Look and the thumbnail read it when they open a file, so a change applies to the next
/// window / preview / icon.
public enum RendererKind: String, Sendable, Hashable, CaseIterable {
    case realityKit = "realitykit"
    case webKit = "webkit"

    /// What a fresh install (or an unknown stored value) uses.
    public static let `default`: RendererKind = .realityKit

    /// The stored switch; `default` when unset or unrecognised.
    public static func stored(in defaults: UserDefaults = AppGroupSettings.defaults) -> RendererKind {
        defaults.string(forKey: AppGroupSettings.Key.renderer).flatMap(RendererKind.init(rawValue:))
            ?? .default
    }

    /// Writes the switch. Only the host process can reach the group suite (a shell
    /// `defaults write` lands in a different domain).
    public static func store(_ kind: RendererKind, in defaults: UserDefaults = AppGroupSettings.defaults) {
        defaults.set(kind.rawValue, forKey: AppGroupSettings.Key.renderer)
    }
}
