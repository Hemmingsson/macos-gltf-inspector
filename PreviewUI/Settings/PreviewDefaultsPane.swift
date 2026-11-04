import DesignSystem
import SwiftUI

struct PreviewDefaultsPane<Store: SettingsDefaultsStore>: View {
    var store: Store

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

            // App defaults, not per-window: this is what thumbnails and Quick Look read, so a
            // file's Finder icon matches how it opens.
            Section {
                DSMenuPicker(
                    "Environment",
                    selection: catalogBinding,
                    options: catalog.map(\.raw)
                ) { raw in
                    catalog.first { $0.raw == raw }?.title ?? raw
                }
                DSMenuPicker(
                    "Tone mapping",
                    selection: toneMappingBinding,
                    options: ToneMapping.allCases
                ) { $0.title }
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

    private var catalogBinding: Binding<String> {
        Binding(
            get: { store.value(for: .environmentCatalog) },
            set: { store.set($0, for: .environmentCatalog) }
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
}
