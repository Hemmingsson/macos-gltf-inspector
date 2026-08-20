import Foundation

enum KhronosEnvironments: String, CaseIterable, Sendable {
    case field = "field"
    case studioNeutral = "neutral"
    case colorfulStudio = "Colorful_Studio"

    static var defaultLook: Self { .studioNeutral }

    var title: String {
        switch self {
        case .field: "Field"
        case .studioNeutral: "Studio Neutral"
        case .colorfulStudio: "Colorful Studio"
        }
    }

    /// Bundle resource name without extension (`assets/ibl/khronos/<rawValue>.hdr`).
    var resourceName: String { rawValue }
}
