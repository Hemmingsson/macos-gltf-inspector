import AppKit
import Sparkle
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsAppearance.apply(
            UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? SettingsAppearance.system.rawValue
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if UserDefaults.standard.object(forKey: SettingsKeys.quitWhenLastWindowCloses) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: SettingsKeys.quitWhenLastWindowCloses)
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.background: PreviewBackground.window.rawValue,
        ])
        updaterController = SPUStandardUpdaterController(
            startingUpdater: GLBUpdateConfig.shouldStartUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 740)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }

        Settings {
            SettingsRootView()
        }
    }
}
