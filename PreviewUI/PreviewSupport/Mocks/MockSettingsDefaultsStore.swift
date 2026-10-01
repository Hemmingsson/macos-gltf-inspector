import Foundation
import Observation

/// Dev-time `SettingsDefaultsStore` for `#Preview` — in-memory app defaults.
@MainActor
@Observable
public final class MockSettingsDefaultsStore: SettingsDefaultsStore {
    private var values: [String: any Sendable] = [:]

    public init() {}

    public func value<Value>(for key: SettingKey<Value>) -> Value {
        values[key.name] as? Value ?? key.fallback
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let sendable = value as? any Sendable else { return }
        values[key.name] = sendable
    }
}
