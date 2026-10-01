import Foundation

/// A typed settings key. `fallback` is what a fresh install uses.
public struct SettingKey<Value: Sendable>: Sendable {
    /// Storage name; matches `AppGroupSettings.Key` in the host (asserted by
    /// `AppGroupSettingsTests`) so the engine adapter is a pass-through.
    public let name: String
    public let fallback: Value

    public init(name: String, fallback: Value) {
        self.name = name
        self.fallback = fallback
    }
}

public extension SettingKey where Value == Bool {
    /// Default on for a new window.
    static var autoRotate: SettingKey<Bool> { .init(name: "settings.preview.autoRotate", fallback: true) }
    /// Floor on for a new window; Settings can set a different app default.
    /// Matches the fresh-install default in `AppGroupSettings.defaultValues`.
    static var showFloor: SettingKey<Bool> { .init(name: "settings.preview.showFloor", fallback: true) }
    /// Session-only. Never registered as a persisted app default.
    static var center: SettingKey<Bool> { .init(name: "settings.preview.center", fallback: true) }
    static var useEnvironmentMap: SettingKey<Bool> { .init(name: "settings.preview.useEnvironmentMap", fallback: true) }
}

public extension SettingKey where Value == BackdropStyle {
    /// Window backdrop ("None") for a new window.
    /// Matches the fresh-install default in `AppGroupSettings.defaultValues`.
    static var backdrop: SettingKey<BackdropStyle> { .init(name: "settings.preview.background", fallback: .window) }
}

public extension SettingKey where Value == Projection {
    /// Session-only. Never registered as a persisted app default.
    static var projection: SettingKey<Projection> { .init(name: "settings.preview.projection", fallback: .perspective) }
}

public extension SettingKey where Value == String {
    static var appearance: SettingKey<String> { .init(name: "settings.general.appearance", fallback: "system") }
    /// `KhronosEnvironments.rawValue` (`neutral` / `field` / `Colorful_Studio`).
    static var environmentCatalog: SettingKey<String> { .init(name: "settings.preview.environmentCatalog", fallback: "neutral") }
    /// Stored as the Khronos tone-map name so the extensions can read it without linking this
    /// framework — see `AppGroupSettings.rendererLook()` in GLTFCore.
    static var toneMapping: SettingKey<String> { .init(name: "settings.preview.toneMapping", fallback: "Khronos PBR Neutral") }
    static var customEnvironmentFile: SettingKey<String> { .init(name: "settings.preview.customEnvironmentFile", fallback: "") }
    /// `RendererKind.rawValue` (`realitykit` / `webkit`). Read by the window, Quick Look and the
    /// thumbnail when they open a file.
    static var renderer: SettingKey<String> { .init(name: "settings.preview.renderer", fallback: "realitykit") }
}
