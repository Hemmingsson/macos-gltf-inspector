import SwiftUI

/// Three-tab Settings. Writes app defaults only, never a window's own state.
struct SettingsView: View {
    var settings: AppSettings

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane(settings: settings)
            }
            Tab("View", systemImage: "cube.transparent") {
                ViewSettingsPane(settings: settings)
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

struct SettingsFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
