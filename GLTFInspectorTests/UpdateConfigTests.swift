import Foundation
import Testing
@testable import GLTFInspector

struct UpdateConfigTests {
    @Test func feedURLUsesGitHubLatestAppcast() {
        #expect(
            UpdateConfig.feedURL.absoluteString
                == "https://github.com/\(UpdateConfig.githubRepo)/releases/latest/download/appcast.xml"
        )
        #expect(UpdateConfig.githubURL.absoluteString == "https://github.com/\(UpdateConfig.githubRepo)")
        #expect(UpdateConfig.feedURL.scheme == "https")
    }

    @Test func publicEdKeyLooksLikeEd25519Base64() throws {
        let keyData = try #require(Data(base64Encoded: UpdateConfig.publicEdKey))
        #expect(keyData.count == 32)
    }

    @Test func updaterStartFlagMatchesBuildConfiguration() {
#if DEBUG
        #expect(!UpdateConfig.shouldStartUpdater)
#else
        #expect(UpdateConfig.shouldStartUpdater)
#endif
    }

    @Test func hostInfoPlistMatchesUpdateConfig() throws {
        let host = try #require(Bundle(identifier: "lol.mattias.gltf-inspector"))
        #expect(host.bundleURL.pathExtension == "app")
        let info = try #require(host.infoDictionary)
        #expect(info["SUFeedURL"] as? String == UpdateConfig.feedURL.absoluteString)
        #expect(info["SUPublicEDKey"] as? String == UpdateConfig.publicEdKey)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["CFBundleName"] as? String == "glTF Inspector")
        #expect(info["CFBundleDisplayName"] as? String == "glTF Inspector")
    }
}
