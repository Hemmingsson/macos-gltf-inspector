import Foundation
import Testing
@testable import GLBPreview

struct UpdateConfigTests {
    @Test func feedURLUsesGitHubLatestAppcast() {
        #expect(
            GLBUpdateConfig.feedURL.absoluteString
                == "https://github.com/\(GLBUpdateConfig.githubRepo)/releases/latest/download/appcast.xml"
        )
        #expect(GLBUpdateConfig.feedURL.scheme == "https")
    }

    @Test func publicEdKeyLooksLikeEd25519Base64() throws {
        let keyData = try #require(Data(base64Encoded: GLBUpdateConfig.publicEdKey))
        #expect(keyData.count == 32)
    }

    @Test func updaterStartFlagMatchesBuildConfiguration() {
#if DEBUG
        #expect(!GLBUpdateConfig.shouldStartUpdater)
#else
        #expect(GLBUpdateConfig.shouldStartUpdater)
#endif
    }

    @Test func hostInfoPlistMatchesUpdateConfig() throws {
        let host = try #require(Bundle(identifier: "com.laurie.GLBPreview"))
        #expect(host.bundleURL.pathExtension == "app")
        let info = try #require(host.infoDictionary)
        #expect(info["SUFeedURL"] as? String == GLBUpdateConfig.feedURL.absoluteString)
        #expect(info["SUPublicEDKey"] as? String == GLBUpdateConfig.publicEdKey)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == false)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
    }
}
