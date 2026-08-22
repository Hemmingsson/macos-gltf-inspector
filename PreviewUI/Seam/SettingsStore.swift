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
    /// Default on for a new window.
    static var autoRotate: SettingKey<Bool> { .init(name: "settings.preview.autoRotate", fallback: true) }
    /// Floor on for a new window; Settings can promote a different app default.
    /// Matches the fresh-install default registered in `GLTFInspectorApp.init`.
    static var showFloor: SettingKey<Bool> { .init(name: "settings.preview.showFloor", fallback: true) }
    /// Session-only. Never registered as a persisted app default.
    static var center: SettingKey<Bool> { .init(name: "settings.preview.center", fallback: true) }
    /// Host `showToolbar` — pills visible on open.
    static var showPills: SettingKey<Bool> { .init(name: "settings.preview.showToolbar", fallback: true) }
    static var useEnvironmentMap: SettingKey<Bool> { .init(name: "settings.preview.useEnvironmentMap", fallback: true) }
}

extension SettingKey where Value == BackdropStyle {
    /// Window backdrop ("None") for a new window.
    /// Matches the fresh-install default registered in `GLTFInspectorApp.init`.
    static var backdrop: SettingKey<BackdropStyle> { .init(name: "settings.preview.background", fallback: .window) }
}

extension SettingKey where Value == Projection {
    /// Session-only. Never registered as a persisted app default.
    static var projection: SettingKey<Projection> { .init(name: "settings.preview.projection", fallback: .perspective) }
}

extension SettingKey where Value == String {
    static var appearance: SettingKey<String> { .init(name: "settings.general.appearance", fallback: "system") }
    /// `KhronosEnvironments.rawValue` (`neutral` / `field` / `Colorful_Studio`).
    static var environmentCatalog: SettingKey<String> { .init(name: "settings.preview.environmentCatalog", fallback: "neutral") }
    static var customEnvironmentFile: SettingKey<String> { .init(name: "settings.preview.customEnvironmentFile", fallback: "") }
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
