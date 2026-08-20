import AppKit
import SwiftUI

enum SettingsAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func apply(_ raw: String) {
        let appearance = SettingsAppearance(rawValue: raw) ?? .system
        NSApp.appearance = appearance.nsAppearance
    }
}

struct SettingsRootView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Preview", systemImage: "cube.transparent") {
                PreviewSettingsPane()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .scenePadding()
        .frame(maxWidth: 520, minHeight: 240)
    }
}

extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
