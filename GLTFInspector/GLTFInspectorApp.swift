import AppKit
import GLTFCore
import PreviewUI
import Sparkle
import SwiftUI

private let staleWelcomeFrameAutosaveKey = "NSWindow Frame welcome-AppWindow-1"

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !PreviewRuntime.isActive else { return }
        #if DEBUG
        DevLaunch.bootstrap()
        #else
        AppLog.configureFileSink()
        #endif
        AppAppearance.apply(
            AppGroupSettings.defaults.string(forKey: AppGroupSettings.Key.appearance)
                ?? AppAppearance.system.rawValue
        )
        UserDefaults.standard.set("preferred", forKey: "AppleWindowTabbingMode")
        MainMenuSymbols.shared.install()
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
    private let updaterController: SPUStandardUpdaterController?

    init() {
        guard !PreviewRuntime.isActive else {
            updaterController = nil
            return
        }
        AppGroupSettings.registerDefaults()
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
            // Native `NavigationSplitView`: `SidebarCommands()` owns ⌃⌘S and stays in sync with
            // `ShellPanelChrome.columnVisibility`. Host View menu is the cluster twin — never
            // `CommandMenu("View")`.
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                HostViewMenuCommands()
            }
            CommandGroup(after: .appInfo) {
                if let updaterController {
                    CheckForUpdatesView(updater: updaterController.updater)
                }
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
                HostFileMenuCommands()
            }
        }

        // Same pages as the Design Catalog app. The scene title is the Window menu item; choosing
        // it again brings this window forward.
        Window("Design System", id: DesignSystemWindow.id) {
            CatalogRootView()
        }
        .defaultSize(width: 1320, height: 900)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)

        Settings {
            PreviewSettingsRoot(store: AppDefaultsStore.appGroup)
        }
    }
}
