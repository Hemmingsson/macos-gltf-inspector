import Foundation

/// The one settings store shared by the app and both extensions.
///
/// Everything Settings writes lives in the App Group `groupID`: `settings.*` keys in the group's
/// `UserDefaults` suite. The app (not sandboxed) and both sandboxed extensions claim the group,
/// so all three processes resolve the same suite.
public enum AppGroupSettings {
    /// Team-prefixed macOS group: needs no provisioning profile or portal registration.
    public static let groupID = "94A9N4B67S.lol.mattias.gltf-inspector"

    /// Storage names; `AppSettings` in the app reads and writes these.
    /// Stored names are persisted user data; keep them as they are.
    public enum Key {
        public static let autoRotate = "settings.preview.autoRotate"
        public static let background = "settings.preview.background"
        public static let showFloor = "settings.preview.showFloor"
        public static let appearance = "settings.general.appearance"
        public static let toneMapping = "settings.preview.toneMapping"
        /// `LightingEnvironment.rawValue`.
        public static let environment = "settings.preview.environmentCatalog"
    }

    /// Fresh-install values. `register(defaults:)` is per process: the app registers them at
    /// launch and `look` before an extension reads.
    public static var defaultValues: [String: Any] {
        [
            Key.background: "window",
            Key.autoRotate: false,
            Key.showFloor: true,
            Key.toneMapping: RenderLook.standard.toneMapping.rawValue,
            Key.environment: RenderLook.standard.environment.rawValue,
        ]
    }

    /// The group suite. Falls back to `.standard` only if the suite cannot be created (a build
    /// without the group entitlement); that case is logged, never silent.
    public static let defaults: UserDefaults = {
        if let suite = UserDefaults(suiteName: groupID) {
            return suite
        }
        AppLog.error(AppLog.settings, "app group suite unavailable; using standard defaults")
        return .standard
    }()

    public static func registerDefaults(in defaults: UserDefaults = defaults) {
        defaults.register(defaults: defaultValues)
    }

    /// The look Settings stored, for surfaces with no window state of their own (Quick Look and
    /// the Finder thumbnail): environment and tone mapping from the suite, everything else
    /// `RenderLook.standard`. Registers the fresh-install defaults first so a caller cannot forget.
    public static func look(defaults: UserDefaults = defaults) -> RenderLook {
        registerDefaults(in: defaults)
        var look = RenderLook.standard
        if let stored = defaults.string(forKey: Key.environment),
           let environment = LightingEnvironment(rawValue: stored) {
            look.environment = environment
        }
        if let stored = defaults.string(forKey: Key.toneMapping),
           let toneMapping = RenderLook.ToneMapping(rawValue: stored) {
            look.toneMapping = toneMapping
        }
        return look
    }
}
