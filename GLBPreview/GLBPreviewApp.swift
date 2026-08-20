import AppKit
import Sparkle
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsAppearance.apply(
            UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? SettingsAppearance.system.rawValue
        )
        // Prefer document tabs on open; users can still tear a tab out into its own window.
        UserDefaults.standard.set("always", forKey: "AppleWindowTabbingMode")
        if wasLaunchedToOpenDocuments() {
            // Welcome uses defaultLaunchBehavior(.presented); dismiss once the run loop settles.
            DispatchQueue.main.async {
                GLBDocumentOpening.closeWelcomeWindows()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if UserDefaults.standard.object(forKey: SettingsKeys.quitWhenLastWindowCloses) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: SettingsKeys.quitWhenLastWindowCloses)
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
            SettingsKeys.playOnOpen: false,
            "NSQuitAlwaysKeepsWindows": false,
            // macOS 26 Liquid Glass defaults to a floating inset sidebar; Finder uses tiled full-height.
            "NSSplitViewItemSidebarDefaultsToFloatingAppearance": false,
        ])
        UserDefaults.standard.set(false, forKey: "NSSplitViewItemSidebarDefaultsToFloatingAppearance")
        updaterController = SPUStandardUpdaterController(
            startingUpdater: GLBUpdateConfig.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        DocumentGroup(viewing: GLBPreviewFileDocument.self) { file in
            ContentView(documentURL: file.fileURL)
        }
        .defaultSize(width: 1200, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(replacing: .saveItem) {}
        }

        WindowGroup(id: WelcomeWindow.id) {
            WelcomeView()
        }
        .defaultSize(width: 1200, height: 740)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        Settings {
            SettingsRootView()
        }
    }
}
