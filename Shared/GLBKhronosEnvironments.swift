import Foundation

enum GLBKhronosEnvironments: String, CaseIterable, Sendable {
    case cannonExterior = "Cannon_Exterior"
    case footprintCourt = "footprint_court"
    case pisa = "pisa"
    case dogesPalace = "doge2"
    case diningRoom = "ennis"
    case field = "field"
    case helipadGoldenhour = "helipad"
    case papermillRuins = "papermill"
    case studioNeutral = "neutral"
    case colorfulStudio = "Colorful_Studio"
    case wideStreet = "Wide_Street"

    static var defaultLook: Self { .studioNeutral }

    static var all: [Self] {
        [
            .cannonExterior, .footprintCourt, .pisa, .dogesPalace, .diningRoom,
            .field, .helipadGoldenhour, .papermillRuins, .studioNeutral,
            .colorfulStudio, .wideStreet,
        ]
    }

    var title: String {
        switch self {
        case .cannonExterior: "Cannon Exterior"
        case .footprintCourt: "Footprint Court"
        case .pisa: "Pisa"
        case .dogesPalace: "Doge's palace"
        case .diningRoom: "Dining room"
        case .field: "Field"
        case .helipadGoldenhour: "Helipad Goldenhour"
        case .papermillRuins: "Papermill Ruins"
        case .studioNeutral: "Studio Neutral"
        case .colorfulStudio: "Colorful Studio"
        case .wideStreet: "Wide Street"
        }
    }

    /// Bundle resource name without extension (`assets/ibl/khronos/<rawValue>.hdr`).
    var resourceName: String { rawValue }
}
