import SwiftUI

enum SettingsEnvironment: String, CaseIterable, Identifiable {
    case cannonExterior
    case footprintCourt
    case pisa
    case dogesPalace
    case diningRoom
    case field
    case helipadGoldenhour
    case papermillRuins
    case studioNeutral
    case colorfulStudio
    case wideStreet

    var id: Self { self }

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
}

struct EnvironmentSettingsPane: View {
    @AppStorage(SettingsKeys.environment) private var environment = SettingsEnvironment.studioNeutral.rawValue

    var body: some View {
        Form {
            Section {
                Picker("Default environment", selection: $environment) {
                    ForEach(SettingsEnvironment.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text("Saved for later. The viewer still uses the bundled studio HDR.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsFormChrome()
        .navigationTitle("Environment")
    }
}
