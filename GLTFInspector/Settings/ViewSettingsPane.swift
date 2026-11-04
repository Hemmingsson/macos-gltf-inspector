import GLTFCore
import SwiftUI

/// How new windows start, and how Quick Look and Finder thumbnails light a file.
struct ViewSettingsPane: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Motion") {
                Toggle("Auto-rotate", isOn: $settings.autoRotates)
                Toggle("Polar floor", isOn: $settings.showsFloor)
            }

            Section("Appearance") {
                DSPicker("Background", selection: $settings.backdrop, options: BackdropStyle.allCases, style: .menu) { $0.title }
            }

            // Quick Look and thumbnails read these too, so a file's Finder icon matches how it opens.
            Section {
                DSPicker("Environment", selection: $settings.environment,
                         options: LightingEnvironment.allCases, style: .menu) { $0.fullTitle }
                DSPicker("Tone mapping", selection: $settings.toneMapping,
                         options: RenderLook.ToneMapping.allCases, style: .menu) { $0.title }
            }
        }
        .settingsFormChrome()
    }
}
