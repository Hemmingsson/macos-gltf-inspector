import Foundation
import Testing
@testable import GLTFInspector

struct UpdateConfigTests {

    @Test func updaterStartFlagMatchesBuildConfiguration() {
#if DEBUG
        #expect(!UpdateConfig.shouldStartUpdater)
#else
        #expect(UpdateConfig.shouldStartUpdater)
#endif
    }

    /// The `SU*` keys are the only copy of the Sparkle config (`project.yml`).
    @Test func hostInfoPlistCarriesTheSparkleConfig() throws {
        let host = try #require(Bundle(identifier: "lol.mattias.gltf-inspector"))
        #expect(host.bundleURL.pathExtension == "app")
        let info = try #require(host.infoDictionary)
        let feed = try #require((info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        #expect(feed.scheme == "https")
        #expect(
            feed.absoluteString
                == "https://github.com/Hemmingsson/macos-gltf-inspector/releases/latest/download/appcast.xml"
        )
        // Ed25519 public key from `generate_keys`: 32 bytes, base64.
        let key = try #require((info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) })
        #expect(key.count == 32)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["CFBundleName"] as? String == "glTF Inspector")
        #expect(info["CFBundleDisplayName"] as? String == "glTF Inspector")
    }
}
