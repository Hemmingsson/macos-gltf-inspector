import GLTFCore
import SwiftUI

/// How new windows start, and how Quick Look and Finder thumbnails light a file.
struct PreviewSettingsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Motion") {
                Toggle("Auto-rotate", isOn: $settings.autoRotates)
                Toggle("Polar floor", isOn: $settings.showsFloor)
            }

            Section("Appearance") {
                DSMenuPicker("Background", selection: $settings.backdrop, options: BackdropStyle.allCases) { $0.title }
            }

            // Quick Look and thumbnails read these too, so a file's Finder icon matches how it opens.
            Section {
                DSMenuPicker("Environment", selection: $settings.environment,
                             options: KhronosEnvironments.allCases) { $0.fullTitle }
                DSMenuPicker("Tone mapping", selection: $settings.toneMapping,
                             options: RenderLook.ToneMapping.allCases) { $0.title }
            }
        }
        .settingsFormChrome()
    }
}
