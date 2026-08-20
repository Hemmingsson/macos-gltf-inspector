import AppKit
import Foundation

enum BlenderLauncher {
    private static let blenderBundleID = "org.blenderfoundation.blender"
    private static let applicationsFallback = URL(fileURLWithPath: "/Applications/Blender.app")

    /// Resolved once per process — install state is stable for a host session.
    private static let resolved = resolve()

    static var isInstalled: Bool { resolved != nil }

    static var applicationURL: URL? { resolved?.app }

    static var applicationIcon: NSImage? {
        guard let app = resolved?.app else { return nil }
        return menuIcon(for: app)
    }

    static func importScript(for fileURL: URL) -> String {
        // `-P` runs before a full operator context exists. `read_homefile` from a
        // top-level `-P` script also aborts the rest of the file — defer via timer,
        // dismiss splash, clear defaults, then import.
        """
        import bpy

        _filepath = \(jsonStringLiteral(fileURL.path))

        def _import_glb():
            try:
                bpy.context.preferences.view.show_splash = False
            except Exception:
                pass
            bpy.ops.object.select_all(action="SELECT")
            bpy.ops.object.delete(use_global=False)
            bpy.ops.import_scene.gltf(filepath=_filepath)
            return None

        bpy.app.timers.register(_import_glb, first_interval=0.1)
        """
    }

    static func openInNewBlenderInstance(_ url: URL) throws {
        guard let executable = resolved?.executable else {
            throw LaunchError.blenderNotInstalled
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-preview-blender-\(UUID().uuidString).py")
        try importScript(for: url).write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--factory-startup", "-P", scriptURL.path]
        do {
            try process.run()
        } catch {
            throw LaunchError.launchFailed(error)
        }

        AppLog.info(AppLog.host, "blender launch \(url.lastPathComponent)")
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: scriptURL)
        }
    }

    private static func resolve() -> (app: URL, executable: URL)? {
        let appURL =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: blenderBundleID)
            ?? (FileManager.default.fileExists(atPath: applicationsFallback.path)
                ? applicationsFallback : nil)
        guard let appURL else { return nil }

        let executable = appURL.appendingPathComponent("Contents/MacOS/Blender")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return (appURL, executable)
    }

    static func menuIcon(for applicationURL: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private static func jsonStringLiteral(_ path: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        // Encoding a `String` always succeeds.
        return String(decoding: try! encoder.encode(path), as: UTF8.self)
    }

    enum LaunchError: LocalizedError {
        case blenderNotInstalled
        case launchFailed(Error)

        var errorDescription: String? {
            switch self {
            case .blenderNotInstalled:
                return "Blender is not installed."
            case .launchFailed(let error):
                return error.localizedDescription
            }
        }
    }
}
