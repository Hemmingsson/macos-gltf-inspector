import Foundation
import Observation

/// Dev-time `SettingsDefaultsStore` for `#Preview` — in-memory app defaults.
@MainActor
@Observable
public final class MockSettingsDefaultsStore: SettingsDefaultsStore {
    private var boolValues: [String: Bool] = [:]
    private var backdropValues: [String: BackdropStyle] = [:]
    private var projectionValues: [String: Projection] = [:]
    private var stringValues: [String: String] = [:]

    public init() {}

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        read(key) ?? key.fallback
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        write(value, for: key)
    }

    private func read<Value>(_ key: SettingKey<Value>) -> Value? {
        if Value.self == Bool.self {
            return boolValues[key.name] as? Value
        }
        if Value.self == BackdropStyle.self {
            return backdropValues[key.name] as? Value
        }
        if Value.self == Projection.self {
            return projectionValues[key.name] as? Value
        }
        if Value.self == String.self {
            return stringValues[key.name] as? Value
        }
        return nil
    }

    private func write<Value>(_ value: Value, for key: SettingKey<Value>) {
        if let boolValue = value as? Bool {
            boolValues[key.name] = boolValue
            return
        }
        if let style = value as? BackdropStyle {
            backdropValues[key.name] = style
            return
        }
        if let projectionValue = value as? Projection {
            projectionValues[key.name] = projectionValue
            return
        }
        if let stringValue = value as? String {
            stringValues[key.name] = stringValue
        }
    }
}
