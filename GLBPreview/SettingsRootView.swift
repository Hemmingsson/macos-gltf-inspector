import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case preview
    case environment

    var id: Self { self }

    var title: String {
        switch self {
        case .preview: "Preview"
        case .environment: "Environment"
        }
    }

    var systemImage: String {
        switch self {
        case .preview: "cube.transparent"
        case .environment: "sun.max"
        }
    }
}

enum SettingsKeys {
    static let autoRotate = "settings.preview.autoRotate"
    static let background = "settings.preview.background"
    static let playOnOpen = "settings.preview.playOnOpen"
    static let showStats = "settings.preview.showStats"
    static let showToolbar = "settings.preview.showToolbar"
    static let defaultCamera = "settings.preview.defaultCamera"
    static let environment = "settings.environment.id"
}

struct SettingsRootView: View {
    @State private var pane: SettingsPane = .preview

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
        } detail: {
            switch pane {
            case .preview:
                PreviewSettingsPane()
            case .environment:
                EnvironmentSettingsPane()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 420)
    }
}

extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
            .settingsScrollEdgeIfAvailable()
    }

    @ViewBuilder
    func settingsScrollEdgeIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
