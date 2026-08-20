import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsAppearance.system.rawValue
    @State private var isDefaultApplication = false
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(SettingsAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .onChange(of: appearance) { _, newValue in
                        SettingsAppearance.apply(newValue)
                    }
                }
            }

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
        .onAppear {
            SettingsAppearance.apply(appearance)
            refreshDefaultApp()
        }
    }

    private var glTFTypes: [UTType] {
        GLBPreviewFileDocument.readableContentTypes
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
                await MainActor.run { refreshDefaultApp() }
            } catch {
                await MainActor.run {
                    defaultAppError = error.localizedDescription
                }
            }
        }
    }
}
