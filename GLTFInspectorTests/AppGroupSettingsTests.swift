import Foundation
@testable import GLTFCore
import Testing
@testable import GLTFInspector
import Renderer

/// One settings store for the app and both extensions: the App Group suite.
@MainActor
struct AppGroupSettingsTests {
    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "gltf.app-group.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// Nothing stored yet: the review-oriented defaults. Khronos PBR Neutral distorts authored
    /// colour least, the right default for a tool whose job is showing what is in the file.
    @Test func aFreshInstallStartsFromTheReviewOrientedDefaults() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.environment == .studioNeutral)
        #expect(settings.toneMapping == .pbrNeutral)
        #expect(settings.backdrop == .window)
        #expect(settings.showsFloor)
        #expect(!settings.autoRotates)
        #expect(AppGroupSettings.rendererLook(defaults: defaults) == .standard)
    }

    /// What Settings writes is what an extension reads from the same suite.
    @Test func settingsWritesReachTheExtensionsReader() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.environment = .field
        settings.toneMapping = .acesHill
        settings.backdrop = .dark

        let look = AppGroupSettings.rendererLook(defaults: defaults)
        #expect(look.environment == .field)
        #expect(look.toneMapping == .acesHill)
        let reread = AppSettings(defaults: defaults)
        #expect(reread.backdrop == .dark && reread.environment == .field && reread.toneMapping == .acesHill)
    }

    /// An environment name this build does not bundle falls back to the default.
    @Test func unknownStoredEnvironmentFallsBackToTheDefault() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("pisa", forKey: AppGroupSettings.Key.environment)
        #expect(AppGroupSettings.rendererLook(defaults: defaults).environment == .defaultLook)
    }

    /// The renderer finds each stored environment's lighting bake by name; a missing one would
    /// leave the model unlit.
    @Test func everyEnvironmentIsBundled() {
        for name in KhronosEnvironments.allCases.map(\.rawValue) + ["shared"] {
            #expect(Bundle(for: MetalRenderer.self).url(forResource: name, withExtension: "metalibl") != nil,
                    "\(name).metalibl missing")
        }
    }

    /// The test host is the app, which claims the group, so the shared settings live there.
    @Test func theAppsSettingsLiveInTheGroupSuite() {
        #expect(AppGroupSettings.defaults !== UserDefaults.standard)
        let key = AppGroupSettings.Key.showFloor
        let previous = AppSettings.shared.showsFloor
        defer { AppSettings.shared.showsFloor = previous }
        AppSettings.shared.showsFloor = !previous
        #expect(AppGroupSettings.defaults.bool(forKey: key) == !previous)
    }
}
