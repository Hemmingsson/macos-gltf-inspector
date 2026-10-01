import AppKit
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
            UserDefaults.standard.string(forKey: SettingsKeys.appearance)
                ?? AppAppearance.system.rawValue
        )
        UserDefaults.standard.set("preferred", forKey: "AppleWindowTabbingMode")
        UserDefaults.standard.removeObject(forKey: staleWelcomeFrameAutosaveKey)
        if wasLaunchedToOpenDocuments() {
            // Welcome uses defaultLaunchBehavior(.presented); dismiss once the run loop settles.
            DispatchQueue.main.async {
                DocumentOpening.closeWelcomeWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
        UserDefaults.standard.register(defaults: [
            SettingsKeys.background: PreviewBackground.window.rawValue,
            SettingsKeys.autoRotate: true,
            SettingsKeys.showFloor: true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        updaterController = SPUStandardUpdaterController(
            startingUpdater: UpdateConfig.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        DocumentGroup(viewing: GLTFInspectorFileDocument.self) { file in
            HostShellRootView(documentURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .restorationBehavior(.disabled)
        .commands {
            // Native `NavigationSplitView`: `SidebarCommands()` owns ⌃⌘S and stays in sync with
            // `ShellPanelChrome.columnVisibility`. Host View menu is the pills twin — never
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
            CommandGroup(replacing: .saveItem) {
                HostFileMenuCommands()
            }
        }

        WindowGroup(id: WelcomeWindow.id) {
            WelcomeView()
        }
        .defaultSize(width: 520, height: 420)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        Settings {
            PreviewSettingsRoot(
                store: EngineAppDefaultsBridge.shared,
                importCustomEnvironment: { url in
                    try EngineAppDefaultsBridge.shared.importCustomEnvironment(from: url)
                }
            )
        }
    }
}
