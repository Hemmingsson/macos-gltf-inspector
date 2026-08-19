import AppKit
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 740)
        .windowResizability(.contentMinSize)
    }
}
