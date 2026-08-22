import Foundation
import Observation

/// App-defaults façade for `PreviewSettingsRoot`: canvas keys → `AppDefaultsStore`,
/// IBL keys → `AppLookStore` (no UserDefaults leak for environment).
@MainActor
@Observable
final class EngineAppDefaultsBridge {
    static let shared = EngineAppDefaultsBridge()

    let defaultsStore: AppDefaultsStore
    let lookStore: AppLookStore

    init(
        defaultsStore: AppDefaultsStore? = nil,
        lookStore: AppLookStore? = nil
    ) {
        self.defaultsStore = defaultsStore ?? .shared
        self.lookStore = lookStore ?? .shared
    }

    func value<Value>(for key: SettingKey<Value>) -> Value {
        if EngineAppLookRouting.isAppLookKey(key) {
            return EngineAppLookRouting.read(key, from: lookStore)
        }
        return defaultsStore.value(for: key)
    }

    func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        if EngineAppLookRouting.isAppLookKey(key) {
            EngineAppLookRouting.write(value, for: key, to: lookStore)
            return
        }
        defaultsStore.set(value, for: key)
    }

    /// Copy + decode-check a custom HDR/EXR into Application Support; returns stored file name.
    func importCustomEnvironment(from source: URL) throws -> String {
        let support = lookStore.directory
        let ibl = AppLook.iblDirectory(in: support)
        try FileManager.default.createDirectory(at: ibl, withIntermediateDirectories: true)

        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        var fileName = source.lastPathComponent
        var dest = ibl.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            fileName = "\(stem)-\(UUID().uuidString.prefix(8)).\(ext)"
            dest = ibl.appendingPathComponent(fileName)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)

        guard PreviewLighting.canDecodeHDR(at: dest) else {
            try? FileManager.default.removeItem(at: dest)
            throw EngineIBLImportError.undecodable(source.lastPathComponent)
        }

        var look = lookStore.look
        look.customFileName = fileName
        look.useEnvironmentMap = true
        lookStore.apply(look)
        return fileName
    }

}

extension EngineAppDefaultsBridge: SettingsDefaultsStore {}

enum EngineIBLImportError: LocalizedError {
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .undecodable(let name):
            "Could not decode \(name). The previous environment is unchanged."
        }
    }
}
