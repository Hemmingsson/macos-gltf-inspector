import AppKit
import SwiftUI

/// Process entry point.
///
/// `--snapshot [dir]` is a **shell-only** development affordance: it renders the view tree to PNG
/// and exits without ever constructing a `Scene`, so no window opens and nothing steals focus.
/// The check has to happen here, before `App.main()` — once SwiftUI owns the run loop a window
/// already exists. See `Snapshots/SnapshotHarness.swift`.
@main
enum PreviewUIShellMain {
    static func main() {
        if CommandLine.arguments.contains("--proof-outliner") {
            if let failure = OutlinerTree.proofFailure() {
                FileHandle.standardError.write(Data("outliner-proof FAIL: \(failure)\n".utf8))
                exit(1)
            }
            AppKitBootstrap.prepareHeadlessSnapshot()
            let liveFailure = MainActor.assumeIsolated { OutlinerLiveProof.failure() }
            if let liveFailure {
                FileHandle.standardError.write(Data("outliner-proof FAIL live: \(liveFailure)\n".utf8))
                exit(1)
            }
            print("outliner-proof PASS (proofFailure + live fold bitmap)")
            exit(0)
        }
        if let request = SnapshotRequest(arguments: CommandLine.arguments) {
            // Headless path first: transform + lock + quiet abort handling *before* AppKit.
            AppKitBootstrap.prepareHeadlessSnapshot()
            // `main()` is the process entry, so this is the main thread; the harness is
            // @MainActor because AppKit hosting is.
            MainActor.assumeIsolated { SnapshotHarness.run(request) }
        }
        AppKitBootstrap.prepareInteractive()
        PreviewUIShellApp.main()
    }
}

/// Shell app: hosts `PreviewUI` against mock data, with no engine anywhere near it.
/// The canvas is injected, so the shell can pass a placeholder where `GLBPreview` passes a
/// `RealityView` — `ShellRootView` itself is identical in both hosts.
struct PreviewUIShellApp: App {
    init() {
        // App-default job only. Session state is per window (MockSettings + MockViewport).
        UserDefaults.standard.register(defaults: [
            SettingKey<Bool>.autoRotate.name: SettingKey<Bool>.autoRotate.fallback,
            SettingKey<Bool>.showFloor.name: SettingKey<Bool>.showFloor.fallback,
            SettingKey<Bool>.center.name: SettingKey<Bool>.center.fallback,
            SettingKey<BackdropStyle>.backdrop.name: SettingKey<BackdropStyle>.backdrop.fallback.rawValue,
            SettingKey<Projection>.projection.name: SettingKey<Projection>.projection.fallback.rawValue,
        ])
    }

    var body: some Scene {
        WindowGroup {
            ShellWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 820)
        .commands {
            // Insert into the system View menu — do **not** add `CommandMenu("View")`.
            CommandGroup(after: .sidebar) {
                ViewMenuCommands()
            }
            // Shell-only acceptance harness (UI-BUILD §2). Binds the *key window* mock via
            // `FocusedValues.mockScene` — not `@State` on `App`.
            CommandMenu("Debug") {
                DebugMenuCommands()
            }
        }

        // Defaults only — canvas pills never write these.
        Settings {
            ShellDefaultsView()
        }
    }
}
