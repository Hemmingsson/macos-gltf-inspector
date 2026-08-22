import AppKit
import Sparkle
import SwiftUI

private let staleWelcomeFrameAutosaveKey = "NSWindow Frame welcome-AppWindow-1"

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.apply(
            UserDefaults.standard.string(forKey: SettingsKeys.appearance)
                ?? AppAppearance.system.rawValue
        )
        UserDefaults.standard.set("preferred", forKey: "AppleWindowTabbingMode")
        UserDefaults.standard.removeObject(forKey: staleWelcomeFrameAutosaveKey)
        if wasLaunchedToOpenDocuments() {
            // Welcome uses defaultLaunchBehavior(.presented); dismiss once the run loop settles.
            DispatchQueue.main.async {
                GLBDocumentOpening.closeWelcomeWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Viewer: prefer welcome on cold launch over restoring prior document windows.
        false
    }

    private func wasLaunchedToOpenDocuments() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        guard event.eventClass == AEEventClass(kCoreEventClass) else { return false }
        return event.eventID == AEEventID(kAEOpenDocuments)
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.background: PreviewBackground.window.rawValue,
            SettingsKeys.autoRotate: true,
            SettingsKeys.showFloor: true,
            "NSQuitAlwaysKeepsWindows": false,
        ])
        updaterController = SPUStandardUpdaterController(
            startingUpdater: GLBUpdateConfig.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        DocumentGroup(viewing: GLBPreviewFileDocument.self) { file in
            HostShellRootView(documentURL: file.fileURL)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .restorationBehavior(.disabled)
        .commands {
            SidebarCommands()
            // Seam-driven View menu (pills twin). Do **not** add `CommandMenu("View")`.
            // Old inline body removed from here; `FocusedPreviewSession` plumbing stays for
            // double-sided / skeleton / FOV until `vfcn76gm` strips leftovers.
            CommandGroup(after: .sidebar) {
                HostViewMenuCommands()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .saveItem) {}
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
