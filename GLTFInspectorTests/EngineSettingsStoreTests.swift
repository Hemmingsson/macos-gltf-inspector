import Foundation
@testable import GLTFCore
import PreviewUI
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
}
