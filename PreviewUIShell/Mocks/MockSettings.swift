import Foundation
import Observation

/// Per-window session overlay on `AppDefaultsStore`. Untouched keys track defaults live.
@MainActor
@Observable
final class MockSettings: SettingsStore {
    let defaultsStore: AppDefaultsStore

    private var sessionBool: [String: Bool] = [:]
    private var sessionBackdrop: [String: BackdropStyle] = [:]
    private var sessionProjection: [String: Projection] = [:]
    private var sessionString: [String: String] = [:]

    init(defaultsStore: AppDefaultsStore = .shared) {
        self.defaultsStore = defaultsStore
    }

    func `default`<Value>(for key: SettingKey<Value>) -> Value {
        defaultsStore.value(for: key)
    }

    func sessionValue<Value>(for key: SettingKey<Value>) -> Value {
        if let override = readSession(key) {
            return override
        }
        return `default`(for: key)
    }

    func setSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        writeSession(value, for: key)
    }

    func promoteToDefault<Value>(_ key: SettingKey<Value>) {
        defaultsStore.set(sessionValue(for: key), for: key)
    }

    func clearSession() {
        sessionBool.removeAll()
        sessionBackdrop.removeAll()
        sessionProjection.removeAll()
        sessionString.removeAll()
    }

    func setDefault<Value>(_ value: Value, for key: SettingKey<Value>) {
        defaultsStore.set(value, for: key)
    }

    private func readSession<Value>(_ key: SettingKey<Value>) -> Value? {
        if Value.self == Bool.self {
            return sessionBool[key.name] as? Value
        }
        if Value.self == BackdropStyle.self {
            return sessionBackdrop[key.name] as? Value
        }
        if Value.self == Projection.self {
            return sessionProjection[key.name] as? Value
        }
        if Value.self == String.self {
            return sessionString[key.name] as? Value
        }
        return nil
    }

    private func writeSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        if let bool = value as? Bool {
            sessionBool[key.name] = bool
            return
        }
        if let style = value as? BackdropStyle {
            sessionBackdrop[key.name] = style
            return
        }
        if let projection = value as? Projection {
            sessionProjection[key.name] = projection
            return
        }
        if let string = value as? String {
            sessionString[key.name] = string
            return
        }
    }
}
