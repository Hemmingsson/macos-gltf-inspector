/// Bundled image-based lights. The raw value names the bake
/// (`Renderer/Environments/<raw>.metalibl`) and is what Settings stores
/// (`AppGroupSettings.Key.environment`).
public enum LightingEnvironment: String, CaseIterable, Sendable, Codable, Identifiable {
    case studioNeutral = "neutral"
    case field = "field"
    case colorfulStudio = "Colorful_Studio"

    public var id: Self { self }

    public static var defaultLook: Self { .studioNeutral }

    /// Short name for the lighting popover.
    public var title: String {
        switch self {
        case .studioNeutral: "Neutral"
        case .field: "Field"
        case .colorfulStudio: "Studio"
        }
    }

    /// Full name for Settings.
    public var fullTitle: String {
        switch self {
        case .studioNeutral: "Studio Neutral"
        case .field: "Field"
        case .colorfulStudio: "Colorful Studio"
        }
    }
}
