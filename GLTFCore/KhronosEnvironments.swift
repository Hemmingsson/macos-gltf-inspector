/// The Khronos Sample Viewer environments the renderer lights with. The raw value names the
/// bundled bake (`Renderer/Environments/<raw>.metalibl`) and is the stored Settings value
/// (`AppGroupSettings.Key.environment`).
public enum KhronosEnvironments: String, CaseIterable, Sendable, Codable {
    case studioNeutral = "neutral"
    case field = "field"
    case colorfulStudio = "Colorful_Studio"

    public static var defaultLook: Self { .studioNeutral }
}
