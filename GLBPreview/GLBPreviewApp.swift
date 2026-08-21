import AppKit
import Sparkle
import SwiftUI

private let staleWelcomeFrameAutosaveKey = "NSWindow Frame welcome-AppWindow-1"

final class GLBAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsAppearance.apply(
            UserDefaults.standard.string(forKey: SettingsKeys.appearance) ?? SettingsAppearance.system.rawValue
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
    @FocusedValue(\.previewCommands) private var previewCommands
    @FocusedValue(\.previewSession) private var previewSession
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
            ContentView(documentURL: file.fileURL)
        }
        .defaultSize(width: 1200, height: 740)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .restorationBehavior(.disabled)
        .commands {
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                // Symbols match PreviewUI Stage / Camera / Look pills (and inspector screenshot).
                Toggle("Show Floor", systemImage: "circle.grid.cross", isOn: session(\.showFloor, true))
                    .disabled(previewSession == nil)
                Toggle(
                    "Auto-Rotate",
                    systemImage: "arrow.trianglehead.counterclockwise.rotate.90",
                    isOn: session(\.autoRotate, true)
                )
                .disabled(previewSession == nil)
                Toggle("Center Model", systemImage: "dot.scope", isOn: session(\.centerModel, true))
                    .disabled(previewSession == nil)
                Toggle("Orthographic", systemImage: "perspective", isOn: session(\.orthographic, false))
                    .disabled(previewSession == nil)
                Toggle("Double-Sided", systemImage: "square.on.square", isOn: session(\.doubleSided, false))
                    .disabled(previewSession == nil)
                Toggle(
                    "Show Skeleton",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isOn: session(\.showSkeleton, false)
                )
                .disabled(previewSession == nil)
                Button("Widen FOV", systemImage: "plus.magnifyingglass") {
                    let fov = session(\.fieldOfViewDegrees, PreviewCamera.defaultFieldOfViewDegrees)
                    fov.wrappedValue = PreviewCamera.clampedFieldOfView(fov.wrappedValue + 5)
                }
                .disabled(previewSession == nil || session(\.orthographic, false).wrappedValue)
                Button("Narrow FOV", systemImage: "minus.magnifyingglass") {
                    let fov = session(\.fieldOfViewDegrees, PreviewCamera.defaultFieldOfViewDegrees)
                    fov.wrappedValue = PreviewCamera.clampedFieldOfView(fov.wrappedValue - 5)
                }
                .disabled(previewSession == nil || session(\.orthographic, false).wrappedValue)
                Button("Reset FOV", systemImage: "arrow.counterclockwise") {
                    session(\.fieldOfViewDegrees, PreviewCamera.defaultFieldOfViewDegrees)
                        .wrappedValue = PreviewCamera.defaultFieldOfViewDegrees
                }
                .disabled(previewSession == nil)
                Divider()
                Button("Fit", systemImage: "viewfinder") {
                    previewCommands?.fit()
                }
                .disabled(previewCommands == nil)
                Button("Reset View", systemImage: "arrow.counterclockwise") {
                    previewCommands?.reset()
                }
                .disabled(previewCommands == nil)
                Button("Screenshot…", systemImage: "camera") {
                    previewCommands?.screenshot()
                }
                .disabled(previewCommands == nil)
                Divider()
                // P3 — session-only camera presets (Camera pill later).
                ForEach(PreviewCamera.CameraPreset.allCases) { preset in
                    Button(preset.title, systemImage: preset.menuSymbol) {
                        previewCommands?.applyCameraPreset(preset)
                    }
                    .disabled(previewCommands == nil)
                }
                Divider()
                // P5 throwaway View-menu lighting (Look pill / sun.max).
                Button("Increase Exposure", systemImage: "sun.max") {
                    session(\.exposureEV, 0).wrappedValue += 0.5
                }
                .disabled(previewSession == nil)
                Button("Decrease Exposure", systemImage: "sun.min") {
                    session(\.exposureEV, 0).wrappedValue -= 0.5
                }
                .disabled(previewSession == nil)
                Button("Reset Exposure", systemImage: "sun.max.circle") {
                    session(\.exposureEV, 0).wrappedValue = 0
                }
                .disabled(previewSession == nil)
                Toggle(
                    "Dim Studio for File Lights",
                    systemImage: "lightbulb.min",
                    isOn: session(\.dimStudioForFileLights, false)
                )
                .disabled(previewSession == nil)
                Button("Rotate Environment 45°", systemImage: "rotate.3d") {
                    session(\.environmentYaw, 0).wrappedValue += .pi / 4
                }
                .disabled(previewSession == nil)
                Button("Reset Environment Rotation", systemImage: "arrow.counterclockwise") {
                    session(\.environmentYaw, 0).wrappedValue = 0
                }
                .disabled(previewSession == nil)
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
            SettingsRootView()
        }
    }

    /// P34 View-menu bindings — fall back to constants when no document window is focused.
    private func session<T>(
        _ keyPath: KeyPath<FocusedPreviewSession, Binding<T>>,
        _ fallback: T
    ) -> Binding<T> {
        previewSession?[keyPath: keyPath] ?? .constant(fallback)
    }
}
