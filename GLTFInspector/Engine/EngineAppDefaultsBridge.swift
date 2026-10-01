import Foundation
import GLTFCore
import Observation
import PreviewUI

/// App-defaults façade for `PreviewSettingsRoot` and each window's `EngineSettingsStore`: canvas
/// keys → `AppDefaultsStore`, IBL keys → `AppLookStore` (no UserDefaults leak for environment).
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
        self.defaultsStore = defaultsStore ?? .appGroup
        self.lookStore = lookStore ?? .shared
    }

    func value<Value>(for key: SettingKey<Value>) -> Value {
        if Self.isAppLookKey(key) {
            return Self.read(key, from: lookStore)
        }
        return defaultsStore.value(for: key)
    }

    func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        if Self.isAppLookKey(key) {
            Self.write(value, for: key, to: lookStore)
            return
        }
        defaultsStore.set(value, for: key)
    }

    /// Copy + decode-check a custom HDR/EXR into the App Group `ibl/`; returns stored file name.
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

        guard EquirectangularImage.canDecode(at: dest) else {
            try? FileManager.default.removeItem(at: dest)
            throw EngineIBLImportError.undecodable(source.lastPathComponent)
        }

        var look = lookStore.look
        look.customFileName = fileName
        look.useEnvironmentMap = true
        lookStore.apply(look)
        return fileName
    }

    // MARK: - IBL keys live on `AppLookStore`, not UserDefaults

    private static func isAppLookKey<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.useEnvironmentMap.name
            || key.name == SettingKey<String>.environmentCatalog.name
            || key.name == SettingKey<String>.customEnvironmentFile.name
    }

    private static func read<Value>(_ key: SettingKey<Value>, from lookStore: AppLookStore) -> Value {
        let look = lookStore.look
        if key.name == SettingKey<Bool>.useEnvironmentMap.name,
           let value = look.useEnvironmentMap as? Value {
            return value
        }
        if key.name == SettingKey<String>.environmentCatalog.name,
           let value = look.catalogRaw as? Value {
            return value
        }
        if key.name == SettingKey<String>.customEnvironmentFile.name {
            let raw = look.customFileName ?? ""
            if let value = raw as? Value {
                return value
            }
        }
        return key.fallback
    }

    private static func write<Value>(_ value: Value, for key: SettingKey<Value>, to lookStore: AppLookStore) {
        var look = lookStore.look
        if key.name == SettingKey<Bool>.useEnvironmentMap.name, let flag = value as? Bool {
            look.useEnvironmentMap = flag
            lookStore.apply(look)
            return
        }
        if key.name == SettingKey<String>.environmentCatalog.name, let raw = value as? String {
            look.catalogRaw = raw
            look.customFileName = nil
            lookStore.apply(look)
            return
        }
        if key.name == SettingKey<String>.customEnvironmentFile.name, let raw = value as? String {
            look.customFileName = raw.isEmpty ? nil : raw
            lookStore.apply(look)
            return
        }
    }
}

extension EngineAppDefaultsBridge: SettingsDefaultsStore {}

extension AppDefaultsStore {
    /// The host's app-defaults store, backed by the App Group suite so the Quick Look and
    /// thumbnail extensions read what Settings writes.
    static let appGroup = AppDefaultsStore(defaults: AppGroupSettings.defaults)
}

enum EngineIBLImportError: LocalizedError {
    case undecodable(String)

    var errorDescription: String? {
        switch self {
        case .undecodable(let name):
            "Could not decode \(name). The previous environment is unchanged."
        }
    }
}
