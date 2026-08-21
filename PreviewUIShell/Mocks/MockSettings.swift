import Foundation
import Observation

/// Shell `SettingsStore`: UserDefaults for **app defaults**, in-memory map for **this window**.
///
/// DESIGN.md three-job rule — canvas pills call `setSession` (via `MockViewport`) and never
/// write defaults. The tiny Settings scene writes UserDefaults only. New windows seed session
/// from defaults once; after that each window is independent.
@MainActor
@Observable
final class MockSettings: SettingsStore {
    /// True after the first `seedSessionFromDefaultsIfNeeded()` — session then stays per-window.
    private(set) var didSeedSession = false

    private var sessionBool: [String: Bool] = [:]
    private var sessionBackdrop: [String: BackdropStyle] = [:]
    private var sessionProjection: [String: Projection] = [:]

    init() {}

    // MARK: - SettingsStore

    func `default`<Value>(for key: SettingKey<Value>) -> Value {
        readDefault(key)
    }

    func sessionValue<Value>(for key: SettingKey<Value>) -> Value {
        if let override = readSession(key) {
            return override
        }
        return readDefault(key)
    }

    func setSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        writeSession(value, for: key)
    }

    func promoteToDefault<Value>(_ key: SettingKey<Value>) {
        writeDefault(sessionValue(for: key), for: key)
    }

    func clearSession() {
        sessionBool.removeAll()
        sessionBackdrop.removeAll()
        sessionProjection.removeAll()
        didSeedSession = false
    }

    // MARK: - Seeding

    /// Copy current app defaults into the session once. Safe to call from `.onAppear`.
    func seedSessionFromDefaultsIfNeeded() {
        guard !didSeedSession else { return }
        setSession(`default`(for: .autoRotate), for: .autoRotate)
        setSession(`default`(for: .showFloor), for: .showFloor)
        setSession(`default`(for: .center), for: .center)
        setSession(`default`(for: .backdrop), for: .backdrop)
        setSession(`default`(for: .projection), for: .projection)
        didSeedSession = true
    }

    /// Write an app default without touching this window's session (Settings scene only).
    func setDefault<Value>(_ value: Value, for key: SettingKey<Value>) {
        writeDefault(value, for: key)
    }

    // MARK: - Typed storage

    private func readDefault<Value>(_ key: SettingKey<Value>) -> Value {
        let defaults = UserDefaults.standard
        if Value.self == Bool.self {
            if defaults.object(forKey: key.name) == nil {
                return key.fallback
            }
            return (defaults.bool(forKey: key.name) as! Value)
        }
        if Value.self == BackdropStyle.self {
            if let raw = defaults.string(forKey: key.name),
               let style = BackdropStyle(rawValue: raw) {
                return style as! Value
            }
            return key.fallback
        }
        if Value.self == Projection.self {
            if let raw = defaults.string(forKey: key.name),
               let projection = Projection(rawValue: raw) {
                return projection as! Value
            }
            return key.fallback
        }
        return key.fallback
    }

    private func writeDefault<Value>(_ value: Value, for key: SettingKey<Value>) {
        let defaults = UserDefaults.standard
        if let bool = value as? Bool {
            defaults.set(bool, forKey: key.name)
            return
        }
        if let style = value as? BackdropStyle {
            defaults.set(style.rawValue, forKey: key.name)
            return
        }
        if let projection = value as? Projection {
            defaults.set(projection.rawValue, forKey: key.name)
            return
        }
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
    }
}
