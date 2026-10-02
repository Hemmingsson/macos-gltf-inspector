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

extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}

struct SettingsFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
private struct SettingsStorePreviewHost<Content: View>: View {
    @State private var store: MockSettingsDefaultsStore
    private let content: (MockSettingsDefaultsStore) -> Content

    init(
        store: MockSettingsDefaultsStore,
        @ViewBuilder content: @escaping (MockSettingsDefaultsStore) -> Content
    ) {
        _store = State(initialValue: store)
        self.content = content
    }

    var body: some View {
        content(store)
    }
}

#Preview("settings root", traits: .fixedLayout(width: 520, height: 380)) {
    SettingsStorePreviewHost(store: SettingsPreviewFixtures.store) { store in
        PreviewSettingsRoot(store: store) { $0.lastPathComponent }
    }
}

#Preview("general", traits: .fixedLayout(width: 520, height: 220)) {
    SettingsStorePreviewHost(store: SettingsPreviewFixtures.store) { store in
        GeneralSettingsPane(store: store)
            .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.generalHeight)
    }
}

#Preview("general dark", traits: .fixedLayout(width: 520, height: 220)) {
    SettingsStorePreviewHost(store: SettingsPreviewFixtures.darkAppearanceStore) { store in
        GeneralSettingsPane(store: store)
            .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.generalHeight)
    }
}

#Preview("preview defaults", traits: .fixedLayout(width: 520, height: 420)) {
    SettingsStorePreviewHost(store: SettingsPreviewFixtures.store) { store in
        PreviewDefaultsPane(store: store) { $0.lastPathComponent }
            .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.previewDefaultsHeight)
    }
}

#Preview("preview defaults custom HDR", traits: .fixedLayout(width: 520, height: 420)) {
    SettingsStorePreviewHost(store: SettingsPreviewFixtures.customHDRStore) { store in
        PreviewDefaultsPane(store: store) { $0.lastPathComponent }
            .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.previewDefaultsHeight)
    }
}

#Preview("about", traits: .fixedLayout(width: 520, height: 200)) {
    AboutSettingsPane()
        .frame(maxWidth: SettingsPreviewMetrics.width, minHeight: SettingsPreviewMetrics.aboutHeight)
}
