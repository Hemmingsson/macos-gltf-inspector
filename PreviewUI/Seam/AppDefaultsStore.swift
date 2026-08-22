import Foundation
import Observation

/// App-wide defaults (UserDefaults). Every window reads this; Settings writes it.
///
/// `revision` bumps on `UserDefaults.didChangeNotification` so windows still on a default
/// (no session override) redraw live when Settings changes that key (P34 lazy overlay).
@MainActor
@Observable
final class AppDefaultsStore {
    static let shared = AppDefaultsStore()

    /// Observation poke — SwiftUI tracks live defaults when Settings changes a key.
    private(set) var revision: UInt64 = 0

    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.revision &+= 1
            }
        }
    }

    func value<Value>(for key: SettingKey<Value>) -> Value {
        _ = revision
        return read(key)
    }

    func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        // Revision bumps only via `didChangeNotification` — avoid a double poke on each write.
        write(value, for: key)
    }

    private func read<Value>(_ key: SettingKey<Value>) -> Value {
        if Value.self == Bool.self {
            if defaults.object(forKey: key.name) == nil {
                return key.fallback
            }
            guard let value = defaults.bool(forKey: key.name) as? Value else {
                return key.fallback
            }
            return value
        }
        if Value.self == BackdropStyle.self {
            if let raw = defaults.string(forKey: key.name),
               let style = BackdropStyle(rawValue: raw),
               let value = style as? Value {
                return value
            }
            return key.fallback
        }
        if Value.self == String.self {
            if let raw = defaults.string(forKey: key.name), let value = raw as? Value {
                return value
            }
            return key.fallback
        }
        return key.fallback
    }

    private func write<Value>(_ value: Value, for key: SettingKey<Value>) {
        if let bool = value as? Bool {
            defaults.set(bool, forKey: key.name)
            return
        }
        if let style = value as? BackdropStyle {
            defaults.set(style.rawValue, forKey: key.name)
            return
        }
        if let string = value as? String {
            defaults.set(string, forKey: key.name)
            return
        }
    }
}
