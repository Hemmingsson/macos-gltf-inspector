import AppKit
import SwiftUI

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GLBLog.processBanner("host-launch")
        GLBWindowLog.start()
        GLBLog.event(GLBLog.host, "applicationDidFinishLaunching windows=\(NSApp.windows.count)")
        GLBWindowLog.dumpWindows("did-finish-launching")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        GLBLog.event(GLBLog.host, "application open urls=\(urls.map(\.path))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        GLBLog.event(GLBLog.host, "last window closed; terminate")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GLBWindowLog.dumpWindows("will-terminate")
        GLBLog.event(GLBLog.host, "applicationWillTerminate")
    }
}

@main
struct GLBPreviewApp: App {
    @NSApplicationDelegateAdaptor(GLBAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    GLBLog.event(GLBLog.window, "WindowGroup ContentView onAppear")
                    GLBWindowLog.dumpWindows("content-appear")
                }
        }
        .defaultSize(width: 810, height: 600)
        .windowResizability(.contentMinSize)
    }
}
