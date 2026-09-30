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
            DocumentWindowRouter(documentURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .commands {
            // Seam-driven View menu (pills twin). Do **not** add `CommandMenu("View")` or
            // `SidebarCommands()` — the app is not a `NavigationSplitView`, so the system sidebar
            // command would be inert and its ⌃⌘S would collide with the toggle below.
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
            #if DEBUG
            CommandMenu("Develop") {
                DevelopMenuCommands()
            }
            #endif
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
