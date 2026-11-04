import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
    @Bindable var settings: AppSettings
    @State private var isDefaultApplication = false
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    private var showsDefaultApp: Bool {
        Bundle.main.bundleIdentifier == "lol.mattias.gltf-inspector"
    }

    var body: some View {
        Form {
            Section("Appearance") {
                DSPicker("Appearance", selection: $settings.appearance, options: AppAppearance.allCases, style: .menu) { $0.title }
                Toggle("Tree guide lines in the layer list", isOn: $settings.showsTreeGuides)
            }

            if showsDefaultApp {
                Section {
                    LabeledContent("Default app") {
                        Button("Set as Default Application") {
                            setAsDefaultApplication()
                        }
                        .disabled(isDefaultApplication)
                    }
                    if let defaultAppName {
                        LabeledContent("Current default") {
                            Text(defaultAppName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    SettingsFooter {
                        Text("macOS may still confirm the change. Finder and Quick Look can keep their own handlers.")
                    }
                }
            }

            if let defaultAppError {
                Section {
                    Text(defaultAppError)
                        .foregroundStyle(Color.red)
                }
            }
        }
        .settingsFormChrome()
        .onAppear {
            refreshDefaultApp()
        }
    }

    private var glTFTypes: [UTType] {
        [UTType(filenameExtension: "glb"), UTType(filenameExtension: "gltf")].compactMap { $0 }
    }

    private func refreshDefaultApp() {
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let handlers = glTFTypes.map { type -> URL? in
            NSWorkspace.shared.urlForApplication(toOpen: type)?.resolvingSymlinksInPath()
        }
        isDefaultApplication = !handlers.isEmpty && handlers.allSatisfy { $0 == appURL }
        defaultAppName = handlers.compactMap { url in
            url.map { FileManager.default.displayName(atPath: $0.path) }
        }.first
    }

    private func setAsDefaultApplication() {
        defaultAppError = nil
        let appURL = Bundle.main.bundleURL
        Task {
            do {
                for type in glTFTypes {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                }
                refreshDefaultApp()
            } catch {
                defaultAppError = error.localizedDescription
            }
        }
    }
}
