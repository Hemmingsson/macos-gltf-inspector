import Foundation
import Observation

/// Dev-time `SettingsDefaultsStore` for `#Preview` — in-memory app defaults.
@MainActor
@Observable
public final class MockSettingsDefaultsStore: SettingsDefaultsStore {
    private var values: [String: Any] = [:]

    public init() {}

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        values[key.name] as? Value ?? key.fallback
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        values[key.name] = value
    }
}
