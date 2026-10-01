import DesignSystem
import SwiftUI

/// Three-tab Settings. Writes app defaults only — never a window session.
public struct PreviewSettingsRoot<Store: SettingsDefaultsStore>: View {
    public var store: Store
    /// Host: copy + decode HDR into Application Support. Shell: store the file name only.
    public var importCustomEnvironment: ((URL) throws -> String)? = nil
    /// Renderers linked into this build (`SettingKey.renderer` raw value + title). The picker
    /// shows only when there is a choice.
    public var renderers: [(raw: String, title: String)] = []

    public init(
        store: Store,
        importCustomEnvironment: ((URL) throws -> String)? = nil,
        renderers: [(raw: String, title: String)] = []
    ) {
        self.store = store
        self.importCustomEnvironment = importCustomEnvironment
        self.renderers = renderers
    }

    public var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane(store: store)
            }
            Tab("Preview", systemImage: "cube.transparent") {
                PreviewDefaultsPane(
                    store: store,
                    importCustomEnvironment: importCustomEnvironment,
                    renderers: renderers
                )
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .scenePadding()
        .frame(maxWidth: 520, minHeight: 240)
    }
}

public extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}

// MARK: - Previews

private enum SettingsPreviewMetrics {
    static let width: CGFloat = 520
    static let rootHeight: CGFloat = 380
    static let generalHeight: CGFloat = 220
    static let previewDefaultsHeight: CGFloat = 420
    static let aboutHeight: CGFloat = 200
}

@MainActor
private enum SettingsPreviewFixtures {
    static var store: MockSettingsDefaultsStore { MockSettingsDefaultsStore() }

    static var darkAppearanceStore: MockSettingsDefaultsStore {
        let store = MockSettingsDefaultsStore()
        store.set("dark", for: .appearance)
        return store
    }

    static var customHDRStore: MockSettingsDefaultsStore {
        let store = MockSettingsDefaultsStore()
        store.set(false, for: .autoRotate)
        store.set(BackdropStyle.white, for: .backdrop)
        store.set("Colorful_Studio", for: .environmentCatalog)
        store.set("studio.hdr", for: .customEnvironmentFile)
        store.set(true, for: .useEnvironmentMap)
        return store
    }
}

@MainActor
private struct PreviewSettingsRootPreviewHost: View {
    @State private var store: MockSettingsDefaultsStore

    init(store: MockSettingsDefaultsStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        PreviewSettingsRoot(store: store) { url in
            url.lastPathComponent
        }
    }
}

@MainActor
private struct GeneralSettingsPanePreviewHost: View {
    @State private var store: MockSettingsDefaultsStore

    init(store: MockSettingsDefaultsStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        GeneralSettingsPane(store: store)
            .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.generalHeight)
    }
}

@MainActor
private struct PreviewDefaultsPanePreviewHost: View {
    @State private var store: MockSettingsDefaultsStore

    init(store: MockSettingsDefaultsStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        PreviewDefaultsPane(store: store) { url in
            url.lastPathComponent
        }
        .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.previewDefaultsHeight)
    }
}

#Preview("settings root", traits: .fixedLayout(width: 520, height: 380)) {
    PreviewSettingsRootPreviewHost(store: SettingsPreviewFixtures.store)
}

#Preview("general", traits: .fixedLayout(width: 520, height: 220)) {
    GeneralSettingsPanePreviewHost(store: SettingsPreviewFixtures.store)
}

#Preview("general dark", traits: .fixedLayout(width: 520, height: 220)) {
    GeneralSettingsPanePreviewHost(store: SettingsPreviewFixtures.darkAppearanceStore)
}

#Preview("preview defaults", traits: .fixedLayout(width: 520, height: 420)) {
    PreviewDefaultsPanePreviewHost(store: SettingsPreviewFixtures.store)
}

#Preview("preview defaults custom HDR", traits: .fixedLayout(width: 520, height: 420)) {
    PreviewDefaultsPanePreviewHost(store: SettingsPreviewFixtures.customHDRStore)
}

#Preview("about", traits: .fixedLayout(width: 520, height: 200)) {
    AboutSettingsPane()
        .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.aboutHeight)
}
