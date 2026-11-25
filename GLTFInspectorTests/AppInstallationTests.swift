import Foundation
@testable import GLTFInspector
import Testing

struct AppInstallationTests {
    @Test func launchServicesDirectoryHintDoesNotChangeBundleLocation() {
        let copied = URL(fileURLWithPath: "/Applications/glTF Inspector.app", isDirectory: false)
        let launched = URL(fileURLWithPath: "/Applications/glTF Inspector.app/", isDirectory: true)
        #expect(AppInstallationCoordinator.sameLocation(copied, launched))
    }

    @Test func anotherRunningBundleIsNotTheInstallationDestination() {
        let downloaded = URL(fileURLWithPath: "/Users/test/Downloads/glTF Inspector.app", isDirectory: true)
        let installed = URL(fileURLWithPath: "/Applications/glTF Inspector.app", isDirectory: true)
        #expect(!AppInstallationCoordinator.sameLocation(downloaded, installed))
    }

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
