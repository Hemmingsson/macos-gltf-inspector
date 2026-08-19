import Foundation

struct AppLook: Codable, Equatable, Sendable {
    var useEnvironmentMap: Bool
    var catalogRaw: String
    var customFileName: String?

    static let `default` = AppLook(
        useEnvironmentMap: true,
        catalogRaw: GLBKhronosEnvironments.studioNeutral.rawValue,
        customFileName: nil
    )

    var catalog: GLBKhronosEnvironments {
        GLBKhronosEnvironments(rawValue: catalogRaw) ?? .studioNeutral
    }

    static func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GLBPreview", isDirectory: true)
    }

    static func lookURL(in directory: URL) -> URL {
        directory.appendingPathComponent("look.json")
    }

    static func iblDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("ibl", isDirectory: true)
    }

    static func load(from directory: URL) -> AppLook {
        let url = lookURL(in: directory)
        guard let data = try? Data(contentsOf: url),
              let look = try? JSONDecoder().decode(AppLook.self, from: data)
        else {
            return .default
        }
        return look
    }

    func save(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.lookURL(in: directory), options: .atomic)
        } catch {
            GLBLog.error(GLBLog.lighting, "AppLook save failed: \(error)")
        }
    }

    static var current: AppLook {
        load(from: supportDirectory())
    }

    static func saveCurrent(_ look: AppLook) {
        look.save(to: supportDirectory())
    }

    func resolvedHDRURL(bundle: Bundle = .main) -> URL? {
        resolvedHDRURL(in: Self.supportDirectory(), bundle: bundle)
    }

    func resolvedHDRURL(in directory: URL, bundle: Bundle = .main) -> URL? {
        if let name = customFileName, !name.isEmpty {
            let custom = Self.iblDirectory(in: directory).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: custom.path) {
                return custom
            }
        }
        return Self.catalogURL(catalog, bundle: bundle)
    }

    private static func catalogURL(_ environment: GLBKhronosEnvironments, bundle: Bundle) -> URL? {
        if bundle == .main {
            return GLBPreviewLighting.catalogURL(environment)
        }
        let name = environment.resourceName
        return bundle.url(forResource: name, withExtension: "hdr", subdirectory: "khronos")
            ?? bundle.url(forResource: name, withExtension: "hdr")
    }
}
