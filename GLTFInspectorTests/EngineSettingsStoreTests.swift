import Foundation
import Testing
@testable import GLTFInspector

@MainActor
struct EngineSettingsStoreTests {
    @Test func lazyOverlayTracksDefaultsUntilOverridden() throws {
        let suite = "engine.settings.overlay.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-settings-look-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let lookStore = AppLookStore(directory: lookDir)
        let tracking = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)
        let overridden = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)

        defaultsStore.set(true, for: .autoRotate)
        #expect(tracking.sessionValue(for: .autoRotate) == true)

        overridden.setSession(false, for: .autoRotate)
        defaultsStore.set(false, for: .autoRotate)
        #expect(tracking.sessionValue(for: .autoRotate) == false)
        #expect(overridden.sessionValue(for: .autoRotate) == false)

        defaultsStore.set(true, for: .autoRotate)
        #expect(tracking.sessionValue(for: .autoRotate) == true)
        #expect(overridden.sessionValue(for: .autoRotate) == false)

        overridden.clearSession()
        #expect(overridden.sessionValue(for: .autoRotate) == true)
    }

    @Test func centerAndProjectionStaySessionOnly() throws {
        let suite = "engine.settings.session-only.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-settings-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let lookStore = AppLookStore(directory: lookDir)
        let store = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)

        store.setSession(false, for: .center)
        store.setSession(.orthographic, for: .projection)
        store.promoteToDefault(.center)
        store.promoteToDefault(.projection)

        #expect(store.sessionValue(for: .center) == false)
        #expect(store.sessionValue(for: .projection) == .orthographic)
        #expect(defaults.object(forKey: SettingKey<Bool>.center.name) == nil)
        #expect(defaults.object(forKey: SettingKey<Projection>.projection.name) == nil)
        #expect(store.default(for: .center) == true)
        #expect(store.default(for: .projection) == .perspective)

        store.clearSession()
        #expect(store.sessionValue(for: .center) == true)
        #expect(store.sessionValue(for: .projection) == .perspective)
    }

    @Test func environmentKeyPromoteWritesAppLook() throws {
        let suite = "engine.settings.applook.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-settings-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let lookStore = AppLookStore(directory: lookDir)
        let store = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)

        #expect(store.default(for: .useEnvironmentMap) == true)
        #expect(store.default(for: .environmentCatalog) == KhronosEnvironments.studioNeutral.rawValue)
        #expect(store.default(for: .customEnvironmentFile) == "")

        store.setSession(false, for: .useEnvironmentMap)
        store.setSession(KhronosEnvironments.field.rawValue, for: .environmentCatalog)
        store.setSession("studio.hdr", for: .customEnvironmentFile)
        store.promoteToDefault(.useEnvironmentMap)
        store.promoteToDefault(.environmentCatalog)
        store.promoteToDefault(.customEnvironmentFile)

        #expect(lookStore.look.useEnvironmentMap == false)
        #expect(lookStore.look.catalogRaw == KhronosEnvironments.field.rawValue)
        #expect(lookStore.look.customFileName == "studio.hdr")
        #expect(AppLook.load(from: lookDir).customFileName == "studio.hdr")

        // Must not leak into the host UserDefaults suite.
        #expect(defaults.object(forKey: SettingKey<Bool>.useEnvironmentMap.name) == nil)
        #expect(defaults.object(forKey: SettingKey<String>.environmentCatalog.name) == nil)
        #expect(defaults.object(forKey: SettingKey<String>.customEnvironmentFile.name) == nil)
    }

    @Test func canvasPromoteWritesUserDefaults() throws {
        let suite = "engine.settings.canvas.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-settings-canvas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let defaultsStore = AppDefaultsStore(defaults: defaults)
        let lookStore = AppLookStore(directory: lookDir)
        let store = EngineSettingsStore(defaultsStore: defaultsStore, lookStore: lookStore)

        store.setSession(false, for: .showFloor)
        store.setSession(.dark, for: .backdrop)
        store.setSession(false, for: .showPills)
        store.setSession("dark", for: .appearance)
        store.promoteToDefault(.showFloor)
        store.promoteToDefault(.backdrop)
        store.promoteToDefault(.showPills)
        store.promoteToDefault(.appearance)

        #expect(defaultsStore.value(for: .showFloor) == false)
        #expect(defaultsStore.value(for: .backdrop) == .dark)
        #expect(defaultsStore.value(for: .showPills) == false)
        #expect(defaultsStore.value(for: .appearance) == "dark")
        #expect(defaults.bool(forKey: SettingsKeys.showFloor) == false)
        #expect(defaults.string(forKey: SettingsKeys.background) == BackdropStyle.dark.rawValue)
        #expect(defaults.bool(forKey: SettingsKeys.showToolbar) == false)
        #expect(defaults.string(forKey: SettingsKeys.appearance) == "dark")
    }
}
