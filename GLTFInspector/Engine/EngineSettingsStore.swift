import Foundation
import GLTFCore
import Observation
import PreviewUI

/// Per-window lazy overlay on the app defaults (`EngineAppDefaultsBridge`).
///
/// Untouched keys track the observed app default live. `center` / `projection` are
/// session-only — never written as app defaults.
@MainActor
@Observable
final class EngineSettingsStore {
    let appDefaults: EngineAppDefaultsBridge

    /// This window's overrides by key name; a value is always its key's `Value`.
    private var overrides: [String: any Sendable] = [:]

    init(
        defaultsStore: AppDefaultsStore? = nil,
        lookStore: AppLookStore? = nil
    ) {
        appDefaults = EngineAppDefaultsBridge(defaultsStore: defaultsStore, lookStore: lookStore)
    }

    func `default`<Value>(for key: SettingKey<Value>) -> Value {
        Self.isSessionOnly(key) ? key.fallback : appDefaults.value(for: key)
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

    private static func isSessionOnly<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.center.name
            || key.name == SettingKey<Projection>.projection.name
    }
}
