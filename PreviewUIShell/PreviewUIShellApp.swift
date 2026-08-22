import AppKit
import SwiftUI

/// Process entry point.
///
/// `--proof-outliner` is a shell-only headless check (fold raster + pure helpers) that exits
/// before any window opens. Normal launches go through `PreviewUIShellApp`.
@main
enum PreviewUIShellMain {
    static func main() {
        if CommandLine.arguments.contains("--proof-outliner")
            || CommandLine.arguments.contains("--proof-cutover-a") {
            if let failure = OutlinerTree.proofFailure() {
                FileHandle.standardError.write(Data("outliner-proof FAIL: \(failure)\n".utf8))
                exit(1)
            }
            AppKitBootstrap.prepareHeadless()
            let liveFailure = MainActor.assumeIsolated { OutlinerLiveProof.failure() }
            if let liveFailure {
                FileHandle.standardError.write(Data("outliner-proof FAIL live: \(liveFailure)\n".utf8))
                exit(1)
            }
            if CommandLine.arguments.contains("--proof-cutover-a") {
                if let failure = MainActor.assumeIsolated({ SeamLiveProof.failure() }) {
                    FileHandle.standardError.write(Data("seam-proof FAIL: \(failure)\n".utf8))
                    exit(1)
                }
                if let failure = MainActor.assumeIsolated({ SettingsLiveProof.failure() }) {
                    FileHandle.standardError.write(Data("settings-proof FAIL: \(failure)\n".utf8))
                    exit(1)
                }
                print("cutover-a-proof PASS (outliner + seam + lazy overlay)")
                exit(0)
            }
            print("outliner-proof PASS (proofFailure + live fold bitmap)")
            exit(0)
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
            SettingKey<Bool>.showPills.name: SettingKey<Bool>.showPills.fallback,
            SettingKey<Bool>.useEnvironmentMap.name: SettingKey<Bool>.useEnvironmentMap.fallback,
            SettingKey<BackdropStyle>.backdrop.name: SettingKey<BackdropStyle>.backdrop.fallback.rawValue,
            SettingKey<String>.appearance.name: SettingKey<String>.appearance.fallback,
            SettingKey<String>.environmentCatalog.name: SettingKey<String>.environmentCatalog.fallback,
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
            PreviewSettingsRoot(store: AppDefaultsStore.shared)
        }
    }
}
