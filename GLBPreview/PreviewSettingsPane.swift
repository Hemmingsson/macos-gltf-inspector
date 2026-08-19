import SwiftUI

struct PreviewSettingsPane: View {
    @AppStorage(SettingsKeys.autoRotate) private var autoRotate = true
    @AppStorage(SettingsKeys.background) private var background = PreviewBackground.window.rawValue
    @AppStorage(SettingsKeys.playOnOpen) private var playOnOpen = true
    @AppStorage(SettingsKeys.showStats) private var showStats = true
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    @AppStorage(SettingsKeys.defaultCamera) private var defaultCamera = PreviewDefaultCamera.fit.rawValue

    var body: some View {
        Form {
            Section("Motion") {
                Toggle(isOn: $autoRotate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-rotate")
                        Text("Orbit the model when using the Fit camera. Reduced Motion turns this off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $playOnOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play animations on open")
                        Text("Starts the first clip when the file has animations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Appearance") {
                Picker("Background", selection: $background) {
                    ForEach(PreviewBackground.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Picker("Default camera", selection: $defaultCamera) {
                    ForEach(PreviewDefaultCamera.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Quick Look") {
                Toggle("Show file info", isOn: $showStats)
                    .toggleStyle(.switch)
                Toggle("Show toolbar on open", isOn: $showToolbar)
                    .toggleStyle(.switch)
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.preview.title)
    }
}
