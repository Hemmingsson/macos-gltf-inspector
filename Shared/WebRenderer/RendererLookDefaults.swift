import Foundation

/// The app-default look, readable from the sandboxed extensions.
///
/// The one-renderer rule is only half the requirement: Finder thumbnail, Quick Look and the
/// document window must also agree on *how* the model is lit and tone mapped. That means the
/// extensions need the app's settings.
///
/// A sandboxed extension reads `UserDefaults.standard` from its **own container**, so a value the
/// app writes is simply invisible there — during the thumbnail spike that failed silently and the
/// RealityKit path ran while looking like a success. What does work is reading the app's
/// preferences plist as a file, which the extensions' existing home-relative read-only exception
/// permits.
enum RendererLookDefaults {
    /// Mirrors `SettingKeys.environmentCatalog` / `.toneMapping` in `PreviewUI`. Duplicated
    /// deliberately: `Shared/` cannot import `PreviewUI`, which the extensions do not link.
    private static let environmentKey = "settings.preview.environmentCatalog"
    private static let toneMappingKey = "settings.preview.toneMapping"

    private static let appBundleID = "lol.mattias.gltf-inspector"

    static let defaultEnvironment = "neutral"
    static let defaultToneMapping = "Khronos PBR Neutral"

    /// Environment stem and Khronos tone-map name, falling back to the review-oriented defaults.
    static func current() -> (environment: String, toneMapping: String) {
        let values = read()
        return (
            values[environmentKey] as? String ?? defaultEnvironment,
            values[toneMappingKey] as? String ?? defaultToneMapping
        )
    }

    private static func read() -> [String: Any] {
        // In the app, standard defaults *are* this domain. `UserDefaults(suiteName:)` cannot be
        // used for it — that initialiser returns nil when the suite name is the caller's own
        // bundle identifier, which silently reads nothing.
        if Bundle.main.bundleIdentifier == appBundleID {
            let defaults = UserDefaults.standard
            return [
                environmentKey: defaults.object(forKey: environmentKey) as Any,
                toneMappingKey: defaults.object(forKey: toneMappingKey) as Any,
            ].compactMapValues { $0 is NSNull ? nil : $0 }
        }

        // An extension has its own container, so read the app's plist off disk instead.
        guard
            let home = realHomeDirectory(),
            let plist = NSDictionary(contentsOf: home
                .appendingPathComponent("Library/Preferences/\(appBundleID).plist")) as? [String: Any]
        else { return [:] }
        return plist
    }

    /// `NSHomeDirectory()` and `homeDirectoryForCurrentUser` both return the *container* home
    /// inside a sandboxed extension, which is the wrong place and fails silently.
    private static func realHomeDirectory() -> URL? {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else { return nil }
        let path = FileManager.default.string(withFileSystemRepresentation: dir, length: strlen(dir))
        return URL(fileURLWithPath: path)
    }
}
