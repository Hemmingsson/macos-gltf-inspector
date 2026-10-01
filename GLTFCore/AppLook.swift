import Foundation

public enum KhronosEnvironments: String, CaseIterable, Sendable, Codable {
    case field = "field"
    case studioNeutral = "neutral"
    case colorfulStudio = "Colorful_Studio"

    public static var defaultLook: Self { .studioNeutral }

    public var title: String {
        switch self {
        case .field: "Field"
        case .studioNeutral: "Studio Neutral"
        case .colorfulStudio: "Colorful Studio"
        }
    }

    /// This environment's bundled `.hdr`; nil when it is missing from the bundle. The `khronos/`
    /// folder ships once, inside GLTFCore.framework; `Bundle.main` is the appex in an extension,
    /// so never look there.
    public var bundledURL: URL? {
        Bundle(for: CoreBundleToken.self).url(forResource: rawValue, withExtension: "hdr", subdirectory: "khronos")
    }
}

private final class CoreBundleToken {}

public struct AppLook: Codable, Equatable, Sendable {
    public var useEnvironmentMap: Bool
    public var catalogRaw: String
    public var customFileName: String?

    public static let `default` = AppLook(
        useEnvironmentMap: true,
        catalogRaw: KhronosEnvironments.studioNeutral.rawValue,
        customFileName: nil
    )

    public var catalog: KhronosEnvironments {
        KhronosEnvironments(rawValue: catalogRaw) ?? .studioNeutral
    }

    public static func lookURL(in directory: URL) -> URL {
        directory.appendingPathComponent("look.json")
    }

    public static func iblDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("ibl", isDirectory: true)
    }

    public static func load(from directory: URL) -> AppLook {
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

    public func save(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.lookURL(in: directory), options: .atomic)
        } catch {
            AppLog.error(AppLog.lighting, "AppLook save failed: \(error)")
        }
    }

    /// The look in the App Group container (the RealityKit lighting and still paths read it).
    public static var current: AppLook {
        load(from: AppGroupSettings.containerURL)
    }

    public func resolvedHDRURL() -> URL? {
        resolvedHDRURL(in: AppGroupSettings.containerURL)
    }

    public func resolvedHDRURL(in directory: URL) -> URL? {
        if let name = customFileName, !name.isEmpty {
            let custom = Self.iblDirectory(in: directory).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: custom.path) {
                return custom
            }
        }
        return catalog.bundledURL
    }
}

@MainActor
@Observable
public final class AppLookStore {
    public static let shared = AppLookStore(directory: AppGroupSettings.containerURL)

    /// App Group container (or test) directory that holds `look.json` + `ibl/`.
    public let directory: URL
    public var look: AppLook

    public init(directory: URL) {
        self.directory = directory
        self.look = AppLook.load(from: directory)
    }

    public func apply(_ look: AppLook) {
        self.look = look
        look.save(to: directory)
    }
}
