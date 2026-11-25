import AppKit
import Foundation

final class AppInstallationCoordinator {
    static let shared = AppInstallationCoordinator()
    static let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

    private let fileManager = FileManager.default
    private let didAskKey = "didAskToMoveToApplications"

    private init() {}

    static func isInApplications(_ bundleURL: URL, applicationsURL: URL = AppInstallationCoordinator.applicationsURL) -> Bool {
        let bundleDirectory = bundleURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let applicationsDirectory = applicationsURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return bundleDirectory == applicationsDirectory
    }

    func offerMoveIfNeeded(
        bundleURL: URL = Bundle.main.bundleURL,
        applicationsURL: URL = AppInstallationCoordinator.applicationsURL
    ) {
#if DEBUG
        return
#else
        guard !Self.isInApplications(bundleURL, applicationsURL: applicationsURL),
              !UserDefaults.standard.bool(forKey: didAskKey)
        else { return }

        let destination = applicationsURL.appendingPathComponent(bundleURL.lastPathComponent)
        let destinationExists = fileManager.fileExists(atPath: destination.path)
        let alert = NSAlert()
        if destinationExists {
            alert.messageText = "glTF Inspector is already in Applications"
            alert.informativeText = "This copy will keep running. To replace the installed app, quit both copies and drag this app into Applications in Finder."
        } else {
            alert.messageText = "Copy glTF Inspector to Applications?"
            alert.informativeText = "This makes it available in Launchpad and keeps Quick Look and Finder extensions registered reliably."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: destinationExists ? "Keep Running This Copy" : "Copy to Applications")
        if !destinationExists { alert.addButton(withTitle: "Keep Here") }

        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: didAskKey)
            return
        }

        guard !destinationExists else { return }

        do {
            if !fileManager.fileExists(atPath: applicationsURL.path) {
                try fileManager.createDirectory(at: applicationsURL, withIntermediateDirectories: true)
            }
            if !fileManager.fileExists(atPath: destination.path) {
                try fileManager.copyItem(at: bundleURL, to: destination)
            }
            let documentURLs = Array(Set(
                NSDocumentController.shared.documents.compactMap(\.fileURL)
                    + NSApp.windows.compactMap(\.representedURL)
            ))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            let completion: (NSRunningApplication?, Error?) -> Void = { application, error in
                DispatchQueue.main.async {
                    if application?.bundleURL?.resolvingSymlinksInPath() == destination.resolvingSymlinksInPath(), error == nil {
                        NSApp.terminate(nil)
                    } else {
                        self.showFailure(error ?? CocoaError(.executableLoad))
                    }
                }
            }
            if documentURLs.isEmpty {
                NSWorkspace.shared.openApplication(at: destination, configuration: configuration, completionHandler: completion)
            } else {
                NSWorkspace.shared.open(documentURLs, withApplicationAt: destination, configuration: configuration, completionHandler: completion)
            }
        } catch {
            showFailure(error)
        }
#endif
    }

    private func showFailure(_ error: Error) {
        let failure = NSAlert()
        failure.messageText = "Couldn’t install glTF Inspector"
        failure.informativeText = error.localizedDescription
        failure.alertStyle = .warning
        failure.addButton(withTitle: "OK")
        failure.runModal()
    }
}
