import Foundation
import Observation

/// A typed settings key. `fallback` is what a fresh install uses.
struct SettingKey<Value: Sendable>: Sendable {
    /// Storage name; matches the host's `UserDefaults` key so the engine adapter is a pass-through.
    let name: String
    let fallback: Value

    init(name: String, fallback: Value) {
        self.name = name
        self.fallback = fallback
    }
}

extension SettingKey where Value == Bool {
    /// Matches the shell wireframe resting state (`Main@2x.png` / `MockViewport`): on.
    static var autoRotate: SettingKey<Bool> { .init(name: "settings.preview.autoRotate", fallback: true) }
    /// Wireframe resting state is floor off; Settings can promote a different app default.
    static var showFloor: SettingKey<Bool> { .init(name: "settings.preview.showFloor", fallback: false) }
    static var center: SettingKey<Bool> { .init(name: "settings.preview.center", fallback: true) }
}

extension SettingKey where Value == BackdropStyle {
    /// Wireframe resting backdrop is white (not the host's clear "None").
    static var backdrop: SettingKey<BackdropStyle> { .init(name: "settings.preview.background", fallback: .white) }
}

extension SettingKey where Value == Projection {
    static var projection: SettingKey<Projection> { .init(name: "settings.preview.projection", fallback: .perspective) }
}

/// Defaults (the App-default job) plus this window's overrides (the This-window job).
///
/// Storage is the single source of truth; the render reads the effective value via
/// `sessionValue(for:)`. The canvas pills never write defaults — only Settings does,
/// or an explicit `promoteToDefault` (DESIGN.md three-job rule).
@MainActor
protocol SettingsStore: AnyObject, Observable {
    /// The app default, as new windows will open.
    func `default`<Value>(for key: SettingKey<Value>) -> Value
    /// The effective value for this window: the session override when there is one,
    /// otherwise the app default.
    func sessionValue<Value>(for key: SettingKey<Value>) -> Value
    /// Override for this window only.
    func setSession<Value>(_ value: Value, for key: SettingKey<Value>)
    /// Make this window's current value the app default.
    func promoteToDefault<Value>(_ key: SettingKey<Value>)
    /// Drop this window's overrides and fall back to the defaults.
    func clearSession()
}
