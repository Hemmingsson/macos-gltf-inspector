import AppKit
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard QAShotLaunch.isActive else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        Task { await QAShotLaunch.runStandalone() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate

    init() {
        QAShotLaunch.parseCommandLine()
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
    }
}
