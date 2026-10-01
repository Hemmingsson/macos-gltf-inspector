import AppKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsPane<Store: SettingsDefaultsStore>: View {
    var store: Store
    @State private var isDefaultApplication = false
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    private var showsDefaultApp: Bool {
        Bundle.main.bundleIdentifier == "lol.mattias.gltf-inspector"
    }

    var body: some View {
        Form {
            Section("Appearance") {
                DSMenuPicker(
                    "Appearance",
                    selection: appearanceBinding,
                    options: AppAppearance.allCases.map(\.rawValue)
                ) { raw in
                    AppAppearance(rawValue: raw)?.title ?? raw
                }
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
                    Text("macOS may still confirm the change. Finder and Quick Look can keep their own handlers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            AppAppearance.apply(store.value(for: .appearance))
            refreshDefaultApp()
        }
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { store.value(for: .appearance) },
            set: { raw in
                store.set(raw, for: .appearance)
                AppAppearance.apply(raw)
            }
        )
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
                await MainActor.run { refreshDefaultApp() }
            } catch {
                await MainActor.run {
                    defaultAppError = error.localizedDescription
                }
            }
        }
    }
}
