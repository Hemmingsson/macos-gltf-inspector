import Foundation

/// The one settings store shared by the host and both extensions.
///
/// Everything Settings writes lives in the App Group `groupID`: `settings.*` keys in the group's
/// `UserDefaults` suite, and `look.json` + custom `ibl/` files in the group container. The host
/// (not sandboxed) and both sandboxed extensions claim the group, so all three processes resolve
/// the same suite and the same directory.
///
/// Foundation-only and extension-safe on purpose; `PreviewUI` keeps its own `SettingKey`
/// strings because it must not import `Shared/` (`AppGroupSettingsTests` asserts they match).
enum AppGroupSettings {
    /// Team-prefixed macOS group: needs no provisioning profile or portal registration.
    static let groupID = "94A9N4B67S.lol.mattias.gltf-inspector"

    /// Storage names. The only list of `settings.*` keys outside `PreviewUI`.
    enum Key {
        static let autoRotate = "settings.preview.autoRotate"
        static let background = "settings.preview.background"
        static let showToolbar = "settings.preview.showToolbar"
        static let showFloor = "settings.preview.showFloor"
        static let appearance = "settings.general.appearance"
        static let toneMapping = "settings.preview.toneMapping"
        // `useEnvironmentMap` / `environmentCatalog` / `customEnvironmentFile` are not
        // UserDefaults keys: the host routes them into `look.json` (`AppLook`).
    }

    static let defaultEnvironment = KhronosEnvironments.studioNeutral.rawValue
    static let defaultToneMapping = "Khronos PBR Neutral"

    /// Fresh-install values. `register(defaults:)` is per process, so the host and each extension
    /// call `registerDefaults()` before reading.
    static var defaultValues: [String: Any] {
        [
            Key.background: "window",
            Key.autoRotate: true,
            Key.showFloor: true,
            Key.toneMapping: defaultToneMapping,
        ]
    }

    /// The group suite. Falls back to `.standard` only if the suite cannot be created (a build
    /// without the group entitlement); that fallback is logged, never silent.
    static let defaults: UserDefaults = {
        if let suite = UserDefaults(suiteName: groupID) {
            return suite
        }
        AppLog.error(AppLog.lighting, "app group suite unavailable; using standard defaults")
        return .standard
    }()

    /// Group container root: holds `look.json` and `ibl/`. Falls back to the process's own
    /// Application Support folder when the group is not claimed (logged).
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        AppLog.error(AppLog.lighting, "app group container unavailable; using Application Support")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("glTF Inspector", isDirectory: true)
    }

    static func registerDefaults(in defaults: UserDefaults = defaults) {
        defaults.register(defaults: defaultValues)
    }

    /// Environment stem + Khronos tone-map name for the web renderer, as Settings stored them.
    /// Registers the fresh-install defaults first so a caller cannot forget.
    static func rendererLook(
        defaults: UserDefaults = defaults,
        directory: URL = containerURL
    ) -> (environment: String, toneMapping: String) {
        registerDefaults(in: defaults)
        let environment = AppLook.load(from: directory).catalog.rawValue
        let toneMapping = defaults.string(forKey: Key.toneMapping) ?? defaultToneMapping
        // Lets a Quick Look / thumbnail run prove which container the appex resolved.
        AppLog.info(AppLog.lighting, "renderer look \(environment) / \(toneMapping) from \(directory.path)")
        return (environment, toneMapping)
    }
}
