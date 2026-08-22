import Foundation

/// P34 lazy overlay: a window without an override tracks defaults; an override stays put.
enum SettingsLiveProof {
    @MainActor
    static func failure() -> String? {
        let suite = "previewui.settings.proof.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return "could not make suite"
        }
        defaults.removePersistentDomain(forName: suite)
        let store = AppDefaultsStore(defaults: defaults)
        let tracking = MockSettings(defaultsStore: store)
        let overridden = MockSettings(defaultsStore: store)

        store.set(true, for: .autoRotate)
        guard tracking.sessionValue(for: .autoRotate) == true else {
            return "tracking missed initial default"
        }

        overridden.setSession(false, for: .autoRotate)
        store.set(false, for: .autoRotate)
        guard tracking.sessionValue(for: .autoRotate) == false else {
            return "tracking window did not follow default"
        }
        guard overridden.sessionValue(for: .autoRotate) == false else {
            return "overridden window lost its value after default matched it"
        }

        store.set(true, for: .autoRotate)
        guard tracking.sessionValue(for: .autoRotate) == true else {
            return "tracking window did not follow default flip"
        }
        guard overridden.sessionValue(for: .autoRotate) == false else {
            return "overridden window followed a default it should ignore"
        }

        overridden.clearSession()
        guard overridden.sessionValue(for: .autoRotate) == true else {
            return "clearSession did not re-track defaults"
        }

        defaults.removePersistentDomain(forName: suite)
        return nil
    }
}
