import AppKit
import Sparkle
import SwiftUI

private let staleWelcomeFrameAutosaveKey = "NSWindow Frame welcome-AppWindow-1"

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        DevLaunch.bootstrap()
        #else
        AppLog.configureFileSink()
        #endif
        AppSettings.shared.appearance.apply()
        // Every document gets its own window: no tabs, and no tab items in the View menu.
        UserDefaults.standard.removeObject(forKey: "AppleWindowTabbingMode")
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.removeObject(forKey: staleWelcomeFrameAutosaveKey)
        if wasLaunchedToOpenDocuments() {
            // Welcome uses defaultLaunchBehavior(.presented); dismiss once the run loop settles.
            DispatchQueue.main.async {
                DocumentOpening.closeWelcomeWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // As a test host, a test's own window may be the last one; quitting then ends the run.
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Cold-launch-to-welcome is enforced by `.restorationBehavior(.disabled)` on the scenes;
        // opt into secure coding so AppKit doesn't fall back to the legacy path.
        true
    }

    private func wasLaunchedToOpenDocuments() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventClass == AEEventClass(kCoreEventClass) else { return false }
        return event.eventID == AEEventID(kAEOpenDocuments)
    }
}

@main
struct GLTFInspectorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        // AppKit reads this from the app's own domain, not the group suite.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        updaterController = SPUStandardUpdaterController(
            startingUpdater: UpdateConfig.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        DocumentGroup(viewing: GLTFInspectorFileDocument.self) { file in
            DocumentWindow(documentURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)

        WindowGroup(id: WelcomeWindow.id) {
            DocumentWindow(documentURL: nil, closesWelcome: false)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            // ⌘B toggles the sidebar; there is no toolbar button for it. The View menu items go
            // after it, never in a `CommandMenu("View")`.
            CommandGroup(replacing: .sidebar) {
                ToggleSidebarCommand()
            }
            CommandGroup(after: .sidebar) {
                ViewMenuCommands()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .newItem) {
                NewWindowCommand()
            }
            // A viewer never writes: drop Save, Save As and Duplicate, keep the file-management
            // commands. The system Share item stays in `.importExport`.
            CommandGroup(replacing: .saveItem) {
                DocumentFileCommands()
            }
            CommandGroup(after: .importExport) {
                ExportPNGCommand()
            }
        }

        Settings {
            SettingsView(settings: .shared)
        }
    }
}
