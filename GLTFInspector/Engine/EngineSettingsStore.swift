import Foundation
import GLTFCore
import Observation
import PreviewUI

/// Per-window lazy overlay on `AppDefaultsStore`, with environment keys routed to `AppLookStore`.
///
/// Untouched keys track the observed app default live. `center` / `projection` are
/// session-only — never written as app defaults. Environment IBL keys have no host
/// `UserDefaults` entry; they read/write `AppLook` via `AppLookStore.apply(_:)`.
@MainActor
@Observable
final class EngineSettingsStore: SettingsStore {
    let defaultsStore: AppDefaultsStore
    let lookStore: AppLookStore

    /// This window's overrides by key name; a value is always its key's `Value`.
    private var overrides: [String: any Sendable] = [:]

    init(
        defaultsStore: AppDefaultsStore? = nil,
        lookStore: AppLookStore? = nil
    ) {
        self.defaultsStore = defaultsStore ?? .appGroup
        self.lookStore = lookStore ?? .shared
    }

    func `default`<Value>(for key: SettingKey<Value>) -> Value {
        if EngineAppLookRouting.isAppLookKey(key) {
            return EngineAppLookRouting.read(key, from: lookStore)
        }
        if Self.isSessionOnly(key) {
            return key.fallback
        }
        return defaultsStore.value(for: key)
    }

    func sessionValue<Value>(for key: SettingKey<Value>) -> Value {
        if let override = overrides[key.name] as? Value {
            return override
        }
        return `default`(for: key)
    }

    func setSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        overrides[key.name] = value
    }

    func clearSession() {
        overrides.removeAll()
    }

    // MARK: - Key routing

    private static func isSessionOnly<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.center.name
            || key.name == SettingKey<Projection>.projection.name
    }

}
