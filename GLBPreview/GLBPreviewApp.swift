import AppKit
import Sparkle
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate
    private let updaterController: SPUStandardUpdaterController

    init() {
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
        .defaultSize(width: 810, height: 600)
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
