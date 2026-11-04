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
        #expect(SettingKey<BackdropStyle>.backdrop.name == AppGroupSettings.Key.background)
        #expect(SettingKey<String>.appearance.name == AppGroupSettings.Key.appearance)
        #expect(SettingKey<String>.toneMapping.name == AppGroupSettings.Key.toneMapping)
        #expect(SettingKey<String>.environmentCatalog.name == AppGroupSettings.Key.environment)
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
        #expect(defaults.string(forKey: AppGroupSettings.Key.environment) == SettingKey<String>.environmentCatalog.fallback)
        #expect(RenderLook.standard.environment.rawValue == SettingKey<String>.environmentCatalog.fallback)
    }

    /// Nothing stored yet: the review-oriented defaults. Khronos PBR Neutral distorts authored
    /// colour least — the right default for a tool whose job is showing what is in the file.
    @Test
    func readerFallsBackToTheReviewOrientedDefaults() throws {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let look = AppGroupSettings.rendererLook(defaults: defaults)
        #expect(look.environment.rawValue == "neutral")
        #expect(look.toneMapping.rawValue == "Khronos PBR Neutral")
    }

    /// The stored string is what reaches the renderer, so a mismatch between the enum and the
    /// persisted name silently renders with the wrong curve.
    @Test
    func everyToneMappingRoundTripsThroughItsStoredName() {
        for option in ToneMapping.allCases {
            #expect(ToneMapping.fromKhronosName(option.khronosName) == option)
            #expect(RenderLook.ToneMapping(rawValue: option.khronosName) != nil)
        }
    }

    /// Host writes through the same store Settings uses; a reader over the same suite (what each
    /// appex does) sees them.
    @Test
    func hostWritesRoundTripThroughTheReader() throws {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppDefaultsStore(defaults: defaults)

        store.set("field", for: .environmentCatalog)
        store.set("ACES Filmic Tone Mapping (Hill)", for: .toneMapping)

        let look = AppGroupSettings.rendererLook(defaults: defaults)
        #expect(look.environment == .field)
        #expect(look.toneMapping == .acesHill)
    }

    /// An environment name this build does not bundle falls back to the default.
    @Test
    func unknownStoredEnvironmentFallsBackToTheDefault() throws {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("pisa", forKey: AppGroupSettings.Key.environment)
        #expect(AppGroupSettings.rendererLook(defaults: defaults).environment == .defaultLook)
    }

    /// The page serves these by name; a missing `.hdr` would leave the model unlit.
    @Test
    func everyEnvironmentIsBundled() {
        for environment in KhronosEnvironments.allCases {
            #expect(environment.bundledURL != nil, "\(environment.rawValue).hdr missing")
        }
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
        #expect(AppGroupSettings.defaults !== UserDefaults.standard)
    }

    /// The host's default Settings path writes into the group suite, not `.standard`.
    @Test
    func hostSettingsWriteToTheGroupSuite() {
        let key = AppGroupSettings.Key.appearance
        let group = AppGroupSettings.defaults
        let previous = group.object(forKey: key)
        defer { group.set(previous, forKey: key) }

        let probe = "probe-\(UUID().uuidString)"
        AppDefaultsStore.appGroup.set(probe, for: .appearance)

        #expect(group.string(forKey: key) == probe)
        #expect(UserDefaults.standard.string(forKey: key) != probe)
    }
}
