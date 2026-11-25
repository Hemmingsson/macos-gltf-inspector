import AppKit
@testable import GLTFInspector
import Testing

@MainActor
struct AppLifecycleTests {
    @Test func testHostIsRecognizedWithoutLegacyConfigurationEnvironment() {
        // Swift Testing can omit XCTestConfigurationFilePath in an app-hosted run.
        #expect(AppDelegate.isTestHost(environment: [:], hasXCTestCaseClass: true))
    }

    @Test func legacyTestConfigurationStillIdentifiesTestHost() {
        #expect(AppDelegate.isTestHost(
            environment: ["XCTestConfigurationFilePath": "/tmp/test-configuration"],
            hasXCTestCaseClass: false
        ))
    }

    @Test func ordinaryAppProcessIsNotATestHost() {
        #expect(!AppDelegate.isTestHost(environment: [:], hasXCTestCaseClass: false))
    }

    @Test func hostedDelegateDoesNotTerminateWhenLastTestWindowCloses() {
        // Exercise the real callback, not only the pure detection rule. No window is
        // closed here: doing so before this regression was fixed could end the runner.
        #expect(NSClassFromString("XCTestCase") != nil)
        #expect(!AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
