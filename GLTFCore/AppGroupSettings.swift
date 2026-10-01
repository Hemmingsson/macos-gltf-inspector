import Foundation

/// The one settings store shared by the host and both extensions.
///
/// Everything Settings writes lives in the App Group `groupID`: `settings.*` keys in the group's
/// `UserDefaults` suite, and `look.json` + custom `ibl/` files in the group container. The host
/// (not sandboxed) and both sandboxed extensions claim the group, so all three processes resolve
/// the same suite and the same directory.
///
/// Foundation-only and extension-safe on purpose; `PreviewUI` keeps its own `SettingKey`
/// strings because it must not import `GLTFCore` (`AppGroupSettingsTests` asserts they match).
public enum AppGroupSettings {
    /// Team-prefixed macOS group: needs no provisioning profile or portal registration.
    public static let groupID = "94A9N4B67S.lol.mattias.gltf-inspector"

    /// Storage names. The only list of `settings.*` keys outside `PreviewUI`.
    public enum Key {
        public static let autoRotate = "settings.preview.autoRotate"
        public static let background = "settings.preview.background"
        public static let showFloor = "settings.preview.showFloor"
        public static let appearance = "settings.general.appearance"
        public static let toneMapping = "settings.preview.toneMapping"
        /// Developer switch, hidden from Settings (`RendererKind`).
        public static let renderer = "settings.preview.renderer"
        // `useEnvironmentMap` / `environmentCatalog` / `customEnvironmentFile` are not
        // UserDefaults keys: the host routes them into `look.json` (`AppLook`).
    }

    /// Fresh-install values. `register(defaults:)` is per process: the host registers them at
    /// launch and `rendererLook` before an extension reads; other extension reads pass their own
    /// fallback.
    public static var defaultValues: [String: Any] {
        [
            Key.background: "window",
            Key.autoRotate: true,
            Key.showFloor: true,
            Key.toneMapping: RenderLook.standard.toneMapping.rawValue,
        ]
    }

    /// The group suite. Falls back to `.standard` only if the suite cannot be created (a build
    /// without the group entitlement); that fallback is logged, never silent.
    public static let defaults: UserDefaults = {
        if let suite = UserDefaults(suiteName: groupID) {
            return suite
        }
        AppLog.error(AppLog.lighting, "app group suite unavailable; using standard defaults")
        return .standard
    }()

    /// Group container root: holds `look.json` and `ibl/`. Falls back to the process's own
    /// Application Support folder when the group is not claimed (logged).
    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        AppLog.error(AppLog.lighting, "app group container unavailable; using Application Support")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("glTF Inspector", isDirectory: true)
    }

    public static func registerDefaults(in defaults: UserDefaults = defaults) {
        defaults.register(defaults: defaultValues)
    }

    /// The look Settings stored, for surfaces with no window state of their own (Quick Look and
    /// the Finder thumbnail): the environment from `look.json`, the tone mapping from the suite,
    /// everything else `RenderLook.standard`. Registers the fresh-install defaults first so a
    /// caller cannot forget.
    public static func rendererLook(
        defaults: UserDefaults = defaults,
        directory: URL = containerURL
    ) -> RenderLook {
        registerDefaults(in: defaults)
        var look = RenderLook.standard
        look.environment = AppLook.load(from: directory).catalog
        if let stored = defaults.string(forKey: Key.toneMapping),
           let toneMapping = RenderLook.ToneMapping(rawValue: stored) {
            look.toneMapping = toneMapping
        }
        return look
    }
}
