import AppKit
import Sparkle
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsAppearance.apply(
            UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? SettingsAppearance.system.rawValue
        )
        guard QAShotLaunch.isActive else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        Task { await QAShotLaunch.runStandalone() }
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
        QAShotLaunch.parseCommandLine()
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
        .defaultSize(
            width: QAShotLaunch.isActive ? 960 : 1200,
            height: QAShotLaunch.isActive ? 640 : 740
        )
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
