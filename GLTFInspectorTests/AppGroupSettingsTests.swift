import Foundation
@testable import GLTFCore
import PreviewUI
import Testing
@testable import GLTFInspector

/// One settings store for host + both extensions: the App Group suite and container.
@MainActor
struct AppGroupSettingsTests {
    /// `PreviewUI` cannot import `GLTFCore`, so its `SettingKey` names are a second copy of
    /// `AppGroupSettings.Key`. A drift here means Settings writes a key the extensions never read.
    @Test
    func previewUIKeyNamesMatchTheGroupKeys() {
        #expect(SettingKey<Bool>.autoRotate.name == AppGroupSettings.Key.autoRotate)
        #expect(SettingKey<Bool>.showFloor.name == AppGroupSettings.Key.showFloor)
        #expect(SettingKey<Bool>.showPills.name == AppGroupSettings.Key.showToolbar)
        #expect(SettingKey<BackdropStyle>.backdrop.name == AppGroupSettings.Key.background)
        #expect(SettingKey<String>.appearance.name == AppGroupSettings.Key.appearance)
        #expect(SettingKey<String>.toneMapping.name == AppGroupSettings.Key.toneMapping)
    }

    /// Registered fallbacks agree with what `PreviewUI` shows on a fresh install.
    @Test
    func registeredDefaultsMatchPreviewUIFallbacks() throws {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        AppGroupSettings.registerDefaults(in: defaults)

        #expect(defaults.bool(forKey: AppGroupSettings.Key.autoRotate) == SettingKey<Bool>.autoRotate.fallback)
        #expect(defaults.bool(forKey: AppGroupSettings.Key.showFloor) == SettingKey<Bool>.showFloor.fallback)
        #expect(defaults.string(forKey: AppGroupSettings.Key.background) == SettingKey<BackdropStyle>.backdrop.fallback.rawValue)
        #expect(defaults.string(forKey: AppGroupSettings.Key.toneMapping) == SettingKey<String>.toneMapping.fallback)
        #expect(AppGroupSettings.defaultEnvironment == SettingKey<String>.environmentCatalog.fallback)
    }

    /// Host writes through the same adapters Settings uses; a reader over the same suite and
    /// directory (what each appex does) sees them.
    @Test
    func hostWritesRoundTripThroughTheReader() throws {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: dir)
        }
        let bridge = EngineAppDefaultsBridge(
            defaultsStore: AppDefaultsStore(defaults: defaults),
            lookStore: AppLookStore(directory: dir)
        )

        bridge.set("field", for: .environmentCatalog)
        bridge.set("ACES Filmic Tone Mapping (Hill)", for: .toneMapping)

        let look = AppGroupSettings.rendererLook(defaults: defaults, directory: dir)
        #expect(look.environment == "field")
        #expect(look.toneMapping == "ACES Filmic Tone Mapping (Hill)")
    }

    /// The test host is the app, which claims the group: the container must resolve to the
    /// shared Group Containers folder, not Application Support.
    @Test
    func hostResolvesTheGroupContainer() {
        let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.groupID
        )
        #expect(url != nil)
        #expect(AppGroupSettings.containerURL.path.contains("Group Containers/\(AppGroupSettings.groupID)"))
        #expect(AppLook.supportDirectory() == AppGroupSettings.containerURL)
        #expect(AppGroupSettings.defaults !== UserDefaults.standard)
    }

    /// The host's default Settings path writes into the group suite, not `.standard`.
    @Test
    func hostSettingsWriteToTheGroupSuite() {
        let key = AppGroupSettings.Key.appearance
        let group = AppGroupSettings.defaults
        let previous = group.object(forKey: key)
        defer { group.set(previous, forKey: key) }

        let bridge = EngineAppDefaultsBridge(lookStore: AppLookStore(directory: FileManager.default.temporaryDirectory))
        let probe = "probe-\(UUID().uuidString)"
        bridge.set(probe, for: .appearance)

        #expect(group.string(forKey: key) == probe)
        #expect(UserDefaults.standard.string(forKey: key) != probe)
    }
}
