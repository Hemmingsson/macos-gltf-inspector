import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsAppearance.system.rawValue
    @AppStorage(SettingsKeys.quitWhenLastWindowCloses) private var quitWhenLastWindowCloses = true
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(SettingsAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appearance) { _, newValue in
                    SettingsAppearance.apply(newValue)
                }
            }

            Section {
                Toggle("Quit when last window closes", isOn: $quitWhenLastWindowCloses)
                    .toggleStyle(.switch)
            }

            Section {
                Button("Set as Default Application") {
                    setAsDefaultApplication()
                }
                if let defaultAppName {
                    Text("Current default: \(defaultAppName)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("macOS may still confirm the change. Finder and Quick Look can keep their own handlers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let defaultAppError {
                Section {
                    Text(defaultAppError)
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.general.title)
        .onAppear {
            SettingsAppearance.apply(appearance)
            refreshDefaultAppName()
        }
    }

    private var glTFTypes: [UTType] {
        [UTType("org.khronos.glb"), UTType("org.khronos.gltf")].compactMap { $0 }
    }

    private func refreshDefaultAppName() {
        let names = glTFTypes.compactMap { type -> String? in
            guard let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
            return FileManager.default.displayName(atPath: url.path)
        }
        defaultAppName = names.first
    }

    private func setAsDefaultApplication() {
        defaultAppError = nil
        let appURL = Bundle.main.bundleURL
        let types = glTFTypes
        Task {
            do {
                for type in types {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                }
                await MainActor.run { refreshDefaultAppName() }
            } catch {
                await MainActor.run {
                    defaultAppError = error.localizedDescription
                }
            }
        }
    }
}
