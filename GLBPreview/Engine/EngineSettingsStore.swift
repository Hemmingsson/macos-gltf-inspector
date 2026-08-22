import Foundation
import Observation

/// Per-window lazy overlay on `AppDefaultsStore`, with environment keys routed to `AppLookStore`.
///
/// Untouched keys track the observed app default live (A3c). `center` / `projection` are
/// session-only — never written as app defaults. Environment IBL keys have no host
/// `UserDefaults` entry; they read/write `AppLook` via `AppLookStore.apply(_:)`.
@MainActor
@Observable
final class EngineSettingsStore: SettingsStore {
    let defaultsStore: AppDefaultsStore
    let lookStore: AppLookStore

    private var sessionBool: [String: Bool] = [:]
    private var sessionBackdrop: [String: BackdropStyle] = [:]
    private var sessionProjection: [String: Projection] = [:]
    private var sessionString: [String: String] = [:]

    init(
        defaultsStore: AppDefaultsStore? = nil,
        lookStore: AppLookStore? = nil
    ) {
        self.defaultsStore = defaultsStore ?? .shared
        self.lookStore = lookStore ?? .shared
    }

    func `default`<Value>(for key: SettingKey<Value>) -> Value {
        if Self.isAppLookKey(key) {
            return readAppLookDefault(key)
        }
        if Self.isSessionOnly(key) {
            return key.fallback
        }
        return defaultsStore.value(for: key)
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
        if Self.isSessionOnly(key) {
            return
        }
        let value = sessionValue(for: key)
        if Self.isAppLookKey(key) {
            writeAppLookDefault(value, for: key)
            return
        }
        defaultsStore.set(value, for: key)
    }

    func clearSession() {
        sessionBool.removeAll()
        sessionBackdrop.removeAll()
        sessionProjection.removeAll()
        sessionString.removeAll()
    }

    // MARK: - Session overlay

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

    // MARK: - Key routing

    private static func isSessionOnly<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.center.name
            || key.name == SettingKey<Projection>.projection.name
    }

    private static func isAppLookKey<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.useEnvironmentMap.name
            || key.name == SettingKey<String>.environmentCatalog.name
            || key.name == SettingKey<String>.customEnvironmentFile.name
    }

    // MARK: - AppLook

    private func readAppLookDefault<Value>(_ key: SettingKey<Value>) -> Value {
        let look = lookStore.look
        if key.name == SettingKey<Bool>.useEnvironmentMap.name,
           let value = look.useEnvironmentMap as? Value {
            return value
        }
        if key.name == SettingKey<String>.environmentCatalog.name,
           let value = look.catalogRaw as? Value {
            return value
        }
        if key.name == SettingKey<String>.customEnvironmentFile.name {
            let raw = look.customFileName ?? ""
            if let value = raw as? Value {
                return value
            }
        }
        return key.fallback
    }

    private func writeAppLookDefault<Value>(_ value: Value, for key: SettingKey<Value>) {
        var look = lookStore.look
        if key.name == SettingKey<Bool>.useEnvironmentMap.name, let flag = value as? Bool {
            look.useEnvironmentMap = flag
            lookStore.apply(look)
            return
        }
        if key.name == SettingKey<String>.environmentCatalog.name, let raw = value as? String {
            look.catalogRaw = raw
            lookStore.apply(look)
            return
        }
        if key.name == SettingKey<String>.customEnvironmentFile.name, let raw = value as? String {
            look.customFileName = raw.isEmpty ? nil : raw
            lookStore.apply(look)
            return
        }
    }
}
