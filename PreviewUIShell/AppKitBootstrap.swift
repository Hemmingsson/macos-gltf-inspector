import AppKit
import ApplicationServices
import Darwin
import Foundation

/// Brings AppKit up without the `RegisterApplication` abort that turns agent/CI runs into
/// "PreviewUIShell quit unexpectedly" dialogs.
///
/// Observed failure (macOS 26): touching `NSApplication.shared` while the process is not yet a
/// UI-element app, or while it has no WindowServer session (Cursor agent sandbox), aborts inside
/// `HIServices` → `___RegisterApplication_block_invoke`. That is an uncaught `SIGABRT`, so the
/// system shows the Reopen sheet — and Reopen re-runs the same `--snapshot` argv, looping.
enum AppKitBootstrap {

    /// Exclusive lock so parallel `--snapshot` invocations do not race `RegisterApplication`.
    private static let lockPath = "/tmp/previewuishell-appkit.lock"

    /// Prepare the process for headless rasterization (`--snapshot`). Never returns on failure:
    /// exits with a clear stderr line instead of aborting into Crash Reporter.
    static func prepareHeadlessSnapshot() {
        acquireLock()
        guard hasWindowServerSession() else {
            fputs(
                "snapshot: no WindowServer session (agent sandbox?). "
                    + "Re-run outside the sandbox / with full permissions.\n",
                stderr
            )
            exit(74)
        }
        becomeUIElementApp()
        let app = withAbortConvertedToExit {
            NSApplication.shared
        }
        app.setActivationPolicy(.prohibited)
    }

    /// Prepare for a normal windowed launch. Same RegisterApplication footgun applies when the
    /// process is spawned from a restricted sandbox with a Dock/Reopen path.
    static func prepareInteractive() {
        guard hasWindowServerSession() else {
            fputs(
                "PreviewUIShell: no WindowServer session; cannot open a window.\n",
                stderr
            )
            exit(74)
        }
        _ = withAbortConvertedToExit {
            NSApplication.shared
        }
    }

    // MARK: - Internals

    private static func hasWindowServerSession() -> Bool {
        CGSessionCopyCurrentDictionary() != nil
    }

    /// Prefer UI-element *before* `NSApplication` init so menu-bar presentation does not run
    /// during `RegisterApplication` (the abort stack we keep seeing).
    private static func becomeUIElementApp() {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
        _ = TransformProcessType(
            &psn,
            ProcessApplicationTransformState(kProcessTransformToUIElementApplication)
        )
    }

    private static func acquireLock() {
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return }
        // Hold for process lifetime; OS releases on exit. Blocking is intentional.
        _ = flock(fd, LOCK_EX)
    }

    /// `RegisterApplication` calls `abort()` on failure. Convert that into a quiet `_exit(74)`
    /// so Crash Reporter does not spam Reopen dialogs during the narrow init window.
    private static func withAbortConvertedToExit<T>(_ work: () -> T) -> T {
        let handler: @convention(c) (Int32) -> Void = { _ in
            let msg = "PreviewUIShell: AppKit RegisterApplication aborted; exiting quietly.\n"
            _ = msg.withCString { write(STDERR_FILENO, $0, strlen($0)) }
            _exit(74)
        }
        let previous = signal(SIGABRT, handler)
        defer { signal(SIGABRT, previous) }
        return work()
    }
}
