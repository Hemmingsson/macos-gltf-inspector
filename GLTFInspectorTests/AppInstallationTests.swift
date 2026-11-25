import Foundation
@testable import GLTFInspector
import Testing

struct AppInstallationTests {
    @Test func bundleInsideApplicationsIsAlreadyInstalled() {
        let bundle = URL(fileURLWithPath: "/Applications/glTF Inspector.app")
        let applications = URL(fileURLWithPath: "/Applications")

        #expect(AppInstallationCoordinator.isInApplications(bundle, applicationsURL: applications))
    }

    @Test func bundleOutsideApplicationsShouldBeOfferedForInstallation() {
        let bundle = URL(fileURLWithPath: "/Users/test/Downloads/glTF Inspector.app")
        let applications = URL(fileURLWithPath: "/Applications")

        #expect(!AppInstallationCoordinator.isInApplications(bundle, applicationsURL: applications))
    }
}
