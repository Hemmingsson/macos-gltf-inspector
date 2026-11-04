import Foundation

/// The bundled Khronos image-based lighting environments. The raw value is the `.hdr` file's
/// stem and the stored Settings value (`AppGroupSettings.Key.environment`).
public enum KhronosEnvironments: String, CaseIterable, Sendable, Codable {
    case field = "field"
    case studioNeutral = "neutral"
    case colorfulStudio = "Colorful_Studio"

    public static var defaultLook: Self { .studioNeutral }

    /// This environment's bundled `.hdr`; nil when it is missing from the bundle. The `khronos/`
    /// folder ships once, inside GLTFCore.framework; `Bundle.main` is the appex in an extension,
    /// so never look there.
    public var bundledURL: URL? {
        Bundle(for: CoreBundleToken.self).url(forResource: rawValue, withExtension: "hdr", subdirectory: "khronos")
    }
}

private final class CoreBundleToken {}
