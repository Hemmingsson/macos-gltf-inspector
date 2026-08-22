import Foundation
import Observation

/// Writable app-defaults surface for Settings panes.
@MainActor
protocol SettingsDefaultsStore: AnyObject, Observable {
    func value<Value>(for key: SettingKey<Value>) -> Value
    func set<Value>(_ value: Value, for key: SettingKey<Value>)
}
