import Foundation
import Testing
@testable import GLTFInspector

@MainActor
struct EngineAppDefaultsBridgeTests {
    @Test func environmentKeysWriteAppLookNotUserDefaults() throws {
        let suite = "engine.appdefaults.bridge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let lookDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-bridge-look-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lookDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: lookDir) }

        let bridge = EngineAppDefaultsBridge(
            defaultsStore: AppDefaultsStore(defaults: defaults),
            lookStore: AppLookStore(directory: lookDir)
        )

        bridge.set(false, for: .useEnvironmentMap)
        bridge.set(KhronosEnvironments.field.rawValue, for: .environmentCatalog)
        #expect(bridge.value(for: .useEnvironmentMap) == false)
        #expect(bridge.value(for: .environmentCatalog) == KhronosEnvironments.field.rawValue)
        #expect(defaults.object(forKey: SettingKey<Bool>.useEnvironmentMap.name) == nil)

        bridge.set(.dark, for: .backdrop)
        bridge.set("dark", for: .appearance)
        #expect(defaults.string(forKey: SettingsKeys.background) == BackdropStyle.dark.rawValue)
        #expect(defaults.string(forKey: SettingsKeys.appearance) == "dark")
    }
}
