import AppKit
import Foundation
import GLTFCore

#if DEBUG
/// Reads `scripts/fixtures.manifest.json` under `GLTF_REPO_ROOT` for dev launches.
enum FixtureCatalog {
    struct Entry: Decodable {
        let id: String
        let label: String
        let path: String
    }

    private struct Manifest: Decodable {
        let fixtures: [Entry]
    }

    static func url(id: String, repoRoot: URL) -> URL? {
        guard let manifest = loadManifest(repoRoot: repoRoot) else { return nil }
        guard let entry = manifest.fixtures.first(where: { $0.id == id }) else { return nil }
        return repoRoot.appendingPathComponent(entry.path)
    }

    private static func loadManifest(repoRoot: URL) -> Manifest? {
        let url = repoRoot.appendingPathComponent("scripts/fixtures.manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }
}

/// DEBUG bootstrap: file logging + optional fixture open via `GLTF_FIXTURE` / `GLTF_REPO_ROOT`.
enum DevLaunch {
    static func bootstrap() {
        applyDevEnvFile()
        AppLog.configureFileSink()
        openFixtureIfNeeded()
    }

    /// Written by `dev.sh run` beside `.build/glTF Inspector.app` — `open` cannot pass env vars.
    private static func applyDevEnvFile() {
        let url = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("dev-env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator])
            let value = String(line[line.index(after: separator)...])
            guard !key.isEmpty, !value.isEmpty else { continue }
            setenv(key, value, 1)
        }
    }

    private static func openFixtureIfNeeded() {
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        if args.contains(where: { $0.hasSuffix(".glb") || $0.hasSuffix(".gltf") }) { return }

        guard let fixture = ProcessInfo.processInfo.environment["GLTF_FIXTURE"], !fixture.isEmpty else { return }
        guard let rootPath = ProcessInfo.processInfo.environment["GLTF_REPO_ROOT"], !rootPath.isEmpty else { return }

        let repoRoot = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let url = FixtureCatalog.url(id: fixture, repoRoot: repoRoot),
              FileManager.default.fileExists(atPath: url.path)
        else {
            AppLog.error(AppLog.host, "dev fixture missing \(fixture)")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error {
                    AppLog.error(
                        AppLog.host,
                        "dev fixture open failed \(url.lastPathComponent): \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
#endif
