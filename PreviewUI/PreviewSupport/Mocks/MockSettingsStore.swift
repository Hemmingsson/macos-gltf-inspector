import Foundation
import Observation

/// Dev-time `SettingsStore` for `#Preview` — in-memory defaults plus per-window overrides.
@MainActor
@Observable
public final class MockSettingsStore: SettingsStore {
    private var defaultsBool: [String: Bool] = [:]
    private var defaultsBackdrop: [String: BackdropStyle] = [:]
    private var defaultsProjection: [String: Projection] = [:]
    private var defaultsString: [String: String] = [:]

    private var sessionBool: [String: Bool] = [:]
    private var sessionBackdrop: [String: BackdropStyle] = [:]
    private var sessionProjection: [String: Projection] = [:]
    private var sessionString: [String: String] = [:]

    public init() {}

    public func `default`<Value>(for key: SettingKey<Value>) -> Value {
        read(key, bool: defaultsBool, backdrop: defaultsBackdrop, projection: defaultsProjection, string: defaultsString)
            ?? key.fallback
    }

    public func sessionValue<Value>(for key: SettingKey<Value>) -> Value {
        read(key, bool: sessionBool, backdrop: sessionBackdrop, projection: sessionProjection, string: sessionString)
            ?? `default`(for: key)
    }

    public func setSession<Value>(_ value: Value, for key: SettingKey<Value>) {
        write(value, for: key, bool: &sessionBool, backdrop: &sessionBackdrop, projection: &sessionProjection, string: &sessionString)
    }

    public func clearSession() {
        sessionBool.removeAll()
        sessionBackdrop.removeAll()
        sessionProjection.removeAll()
        sessionString.removeAll()
    }

    // MARK: - Typed storage

    private func read<Value>(
        _ key: SettingKey<Value>,
        bool: [String: Bool],
        backdrop: [String: BackdropStyle],
        projection: [String: Projection],
        string: [String: String]
    ) -> Value? {
        if Value.self == Bool.self {
            return bool[key.name] as? Value
        }
        if Value.self == BackdropStyle.self {
            return backdrop[key.name] as? Value
        }
        if Value.self == Projection.self {
            return projection[key.name] as? Value
        }
        if Value.self == String.self {
            return string[key.name] as? Value
        }
        return nil
    }

    private func write<Value>(
        _ value: Value,
        for key: SettingKey<Value>,
        bool: inout [String: Bool],
        backdrop: inout [String: BackdropStyle],
        projection: inout [String: Projection],
        string: inout [String: String]
    ) {
        if let boolValue = value as? Bool {
            bool[key.name] = boolValue
            return
        }
        if let style = value as? BackdropStyle {
            backdrop[key.name] = style
            return
        }
        if let projectionValue = value as? Projection {
            projection[key.name] = projectionValue
            return
        }
        if let stringValue = value as? String {
            string[key.name] = stringValue
        }
    }
}
