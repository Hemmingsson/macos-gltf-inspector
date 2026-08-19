import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case preview
    case environment
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .preview: "Preview"
        case .environment: "Environment"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .preview: "cube.transparent"
        case .environment: "sun.max"
        case .about: "info.circle"
        }
    }
}

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
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane {
            case .general:
                GeneralSettingsPane()
            case .preview:
                PreviewSettingsPane()
            case .environment:
                EnvironmentSettingsPane()
            case .about:
                AboutSettingsPane()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 660, minHeight: 420)
    }
}

extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
