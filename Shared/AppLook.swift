import Foundation

enum KhronosEnvironments: String, CaseIterable, Sendable {
    case field = "field"
    case studioNeutral = "neutral"
    case colorfulStudio = "Colorful_Studio"

    static var defaultLook: Self { .studioNeutral }

    var title: String {
        switch self {
        case .field: "Field"
        case .studioNeutral: "Studio Neutral"
        case .colorfulStudio: "Colorful Studio"
        }
    }
}

struct AppLook: Codable, Equatable, Sendable {
    var useEnvironmentMap: Bool
    var catalogRaw: String
    var customFileName: String?

    static let `default` = AppLook(
        useEnvironmentMap: true,
        catalogRaw: KhronosEnvironments.studioNeutral.rawValue,
        customFileName: nil
    )

    var catalog: KhronosEnvironments {
        KhronosEnvironments(rawValue: catalogRaw) ?? .studioNeutral
    }

    static func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("glTF Inspector", isDirectory: true)
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
              var look = try? JSONDecoder().decode(AppLook.self, from: data)
        else {
            return .default
        }
        if KhronosEnvironments(rawValue: look.catalogRaw) == nil {
            look.catalogRaw = KhronosEnvironments.studioNeutral.rawValue
            look.save(to: directory)
        }
        return look
    }

    func save(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.lookURL(in: directory), options: .atomic)
        } catch {
            AppLog.error(AppLog.lighting, "AppLook save failed: \(error)")
        }
    }

    static var current: AppLook {
        load(from: supportDirectory())
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

    private static func catalogURL(_ environment: KhronosEnvironments, bundle: Bundle) -> URL? {
        PreviewLighting.catalogURL(environment, bundle: bundle)
    }
}

@MainActor
@Observable
final class AppLookStore {
    static let shared = AppLookStore(directory: AppLook.supportDirectory())

    /// Application Support (or test) directory that holds `look.json` + `ibl/`.
    let directory: URL
    var look: AppLook

    init(directory: URL) {
        self.directory = directory
        self.look = AppLook.load(from: directory)
    }

    func apply(_ look: AppLook) {
        self.look = look
        look.save(to: directory)
    }
}
