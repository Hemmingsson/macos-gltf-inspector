import Foundation

/// IBL keys live on `AppLookStore`, not UserDefaults. Shared by the per-window overlay
/// and the Settings façade so catalog vs custom-HDR writes cannot drift.
@MainActor
enum EngineAppLookRouting {
    static func isAppLookKey<Value>(_ key: SettingKey<Value>) -> Bool {
        key.name == SettingKey<Bool>.useEnvironmentMap.name
            || key.name == SettingKey<String>.environmentCatalog.name
            || key.name == SettingKey<String>.customEnvironmentFile.name
    }

    static func read<Value>(_ key: SettingKey<Value>, from lookStore: AppLookStore) -> Value {
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

    static func write<Value>(_ value: Value, for key: SettingKey<Value>, to lookStore: AppLookStore) {
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
