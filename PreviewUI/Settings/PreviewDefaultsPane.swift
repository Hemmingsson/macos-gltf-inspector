import AppKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

struct PreviewDefaultsPane<Store: SettingsDefaultsStore>: View {
    var store: Store
    var importCustomEnvironment: ((URL) throws -> String)?
    var renderers: [(raw: String, title: String)] = []
    @State private var importError: String?

    private var catalog: [(raw: String, title: String)] {
        StudioEnvironment.allCases.map { environment in
            (environment.rawValue, settingsTitle(for: environment))
        }
    }

    private func settingsTitle(for environment: StudioEnvironment) -> String {
        switch environment {
        case .neutral: "Studio Neutral"
        case .field: "Field"
        case .colorfulStudio: "Colorful Studio"
        }
    }

    var body: some View {
        Form {
            if renderers.count > 1 {
                Section {
                    DSMenuPicker(
                        "Renderer",
                        selection: rendererBinding,
                        options: renderers.map(\.raw)
                    ) { raw in
                        renderers.first { $0.raw == raw }?.title ?? raw
                    }
                } footer: {
                    SettingsFooter {
                        Text("Applies to new windows, Quick Look previews and Finder thumbnails. Open windows keep their renderer.")
                    }
                }
            }

            Section("Motion") {
                Toggle("Auto-rotate", isOn: boolBinding(for: .autoRotate))
                Toggle("Polar floor", isOn: boolBinding(for: .showFloor))
            }

            Section("Appearance") {
                DSMenuPicker(
                    "Background",
                    selection: backdropBinding,
                    options: Array(BackdropStyle.allCases)
                ) { $0.title }
            }

            Section {
                Toggle("Use environment map", isOn: boolBinding(for: .useEnvironmentMap))
                DSMenuPicker(
                    "Environment",
                    selection: catalogBinding,
                    options: catalog.map(\.raw)
                ) { raw in
                    catalog.first { $0.raw == raw }?.title ?? raw
                }
                // App default, not per-window: this is what thumbnails and Quick Look read,
                // so a file's Finder icon matches how it opens.
                DSMenuPicker(
                    "Tone mapping",
                    selection: toneMappingBinding,
                    options: ToneMapping.allCases
                ) { $0.title }
                Button("Add your own…") {
                    addCustomHDR()
                }
                if !store.value(for: .customEnvironmentFile).isEmpty {
                    Text(store.value(for: .customEnvironmentFile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                SettingsFooter {
                    if let importError {
                        Text(importError)
                            .foregroundStyle(DS.Color.error)
                    } else {
                        Text("Custom HDR and EXR files are remembered for the host lighting path.")
                    }
                }
            }
        }
        .settingsFormChrome()
    }

    private func boolBinding(for key: SettingKey<Bool>) -> Binding<Bool> {
        Binding(
            get: { store.value(for: key) },
            set: { store.set($0, for: key) }
        )
    }

    private var backdropBinding: Binding<BackdropStyle> {
        Binding(
            get: { store.value(for: .backdrop) },
            set: { store.set($0, for: .backdrop) }
        )
    }

    private var rendererBinding: Binding<String> {
        Binding(
            get: { store.value(for: .renderer) },
            set: { store.set($0, for: .renderer) }
        )
    }

    private var catalogBinding: Binding<String> {
        Binding(
            get: { store.value(for: .environmentCatalog) },
            set: { raw in
                store.set(raw, for: .environmentCatalog)
                store.set("", for: .customEnvironmentFile)
            }
        )
    }

    /// Stored as the Khronos tone-map name so the sandboxed extensions can read the raw value
    /// without linking this framework.
    private var toneMappingBinding: Binding<ToneMapping> {
        Binding(
            get: { ToneMapping.fromKhronosName(store.value(for: .toneMapping)) },
            set: { store.set($0.khronosName, for: .toneMapping) }
        )
    }

    private func addCustomHDR() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "hdr"),
            UTType(filenameExtension: "exr"),
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let importCustomEnvironment {
            do {
                let fileName = try importCustomEnvironment(url)
                store.set(fileName, for: .customEnvironmentFile)
                store.set(true, for: .useEnvironmentMap)
                importError = nil
            } catch {
                importError = error.localizedDescription
            }
            return
        }

        store.set(url.lastPathComponent, for: .customEnvironmentFile)
        store.set(true, for: .useEnvironmentMap)
        importError = nil
    }
}
