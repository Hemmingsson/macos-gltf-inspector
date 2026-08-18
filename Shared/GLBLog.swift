import Foundation
import os
import RealityKit
#if canImport(AppKit)
import AppKit
#endif

/// Verbose diagnostics for every preview / thumbnail / window step.
/// Unified Logging (`log stream --predicate 'subsystem == "com.laurie.GLBPreview"'`)
/// plus a best-effort file at `~/Library/Logs/GLBPreview/verbose.log` (host)
/// or the sandbox container (extensions).
enum GLBLog {
    static let subsystem = "com.laurie.GLBPreview"

    static let load = Logger(subsystem: subsystem, category: "load")
    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let window = Logger(subsystem: subsystem, category: "window")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let prepare = Logger(subsystem: subsystem, category: "prepare")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let lighting = Logger(subsystem: subsystem, category: "lighting")
    static let host = Logger(subsystem: subsystem, category: "host")
    static let draco = Logger(subsystem: subsystem, category: "draco")

    private static let fileLock = NSLock()
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let fileURL: URL = {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/GLBPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("verbose.log")
    }()

    static func event(
        _ logger: Logger,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let stamp = iso.string(from: Date())
        let loc = "\(file):\(line) \(function)"
        let text = "[\(stamp)] \(loc) | \(message)"
        logger.info("\(text, privacy: .public)")
        print("[GLBPreview] \(text)")
        appendFile(text)
    }

    static func error(
        _ logger: Logger,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        let stamp = iso.string(from: Date())
        let loc = "\(file):\(line) \(function)"
        let text = "[\(stamp)] ERROR \(loc) | \(message)"
        logger.error("\(text, privacy: .public)")
        print("[GLBPreview] \(text)")
        appendFile(text)
    }

    static func timed<T>(
        _ logger: Logger,
        _ label: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        _ work: () throws -> T
    ) rethrows -> T {
        let start = ContinuousClock.now
        event(logger, "BEGIN \(label)", file: file, function: function, line: line)
        do {
            let value = try work()
            event(
                logger,
                "END \(label) elapsed=\(fmt(start)) ok",
                file: file,
                function: function,
                line: line
            )
            return value
        } catch {
            Self.error(
                logger,
                "END \(label) elapsed=\(fmt(start)) failed \(error)",
                file: file,
                function: function,
                line: line
            )
            throw error
        }
    }

    static func timedAsync<T>(
        _ logger: Logger,
        _ label: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        _ work: () async throws -> T
    ) async rethrows -> T {
        let start = ContinuousClock.now
        event(logger, "BEGIN \(label)", file: file, function: function, line: line)
        do {
            let value = try await work()
            event(
                logger,
                "END \(label) elapsed=\(fmt(start)) ok",
                file: file,
                function: function,
                line: line
            )
            return value
        } catch {
            Self.error(
                logger,
                "END \(label) elapsed=\(fmt(start)) failed \(error)",
                file: file,
                function: function,
                line: line
            )
            throw error
        }
    }

    static func processBanner(_ reason: String) {
        let info = ProcessInfo.processInfo
        let bundle = Bundle.main
        event(
            host,
            """
            process \(reason) pid=\(info.processIdentifier) \
            name=\(info.processName) bundle=\(bundle.bundleIdentifier ?? "?") \
            exe=\(bundle.executablePath ?? "?") \
            args=\(info.arguments) \
            host=\(info.hostName) \
            os=\(info.operatingSystemVersionString)
            """
        )
    }

    @MainActor
    static func describe(_ entity: Entity) -> String {
        var nodes = 0
        var models = 0
        func walk(_ e: Entity) {
            nodes += 1
            if e.components[ModelComponent.self] != nil {
                models += 1
            }
            for child in e.children {
                walk(child)
            }
        }
        walk(entity)
        let bounds = entity.visualBounds(relativeTo: nil)
        let extent = bounds.max - bounds.min
        let anims = entity.availableAnimations
        let names = anims.map { anim -> String in
            let n = anim.name ?? ""
            return n.isEmpty ? "?" : n
        }.joined(separator: ",")
        return """
        name=\(entity.name.isEmpty ? "(root)" : entity.name) nodes=\(nodes) models=\(models) \
        anims=\(anims.count) [\(names)] \
        bounds.min=\(fmt3(bounds.min)) bounds.max=\(fmt3(bounds.max)) \
        extent=\(fmt3(extent)) center=\(fmt3(bounds.center))
        """
    }

    static func describeURL(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .isReadableKey, .isDirectoryKey, .contentTypeKey,
        ])
        let size = values?.fileSize.map(String.init) ?? "?"
        let readable = values?.isReadable.map(String.init) ?? "?"
        return "path=\(url.path) ext=\(url.pathExtension) size=\(size) readable=\(readable)"
    }

    static func fmt3(_ v: SIMD3<Float>) -> String {
        String(format: "(%.4f,%.4f,%.4f)", v.x, v.y, v.z)
    }

    private static func fmt(_ start: ContinuousClock.Instant) -> String {
        let dur = start.duration(to: .now)
        return String(format: "%.3fs", Double(dur.components.seconds) + Double(dur.components.attoseconds) / 1e18)
    }

    private static func appendFile(_ line: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

#if canImport(AppKit)
enum GLBWindowLog {
    private static var started = false
    private static var lastLayout: [Int: String] = [:]

    static func start() {
        guard !started else { return }
        started = true
        GLBLog.processBanner("window-observer")
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didExposeNotification,
            NSApplication.didFinishLaunchingNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.willTerminateNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                handle(note)
            }
        }
        dumpWindows("observer-started")
    }

    static func dumpWindows(_ reason: String) {
        let windows = NSApp.windows
        GLBLog.event(GLBLog.window, "dump reason=\(reason) count=\(windows.count)")
        for (index, window) in windows.enumerated() {
            GLBLog.event(GLBLog.window, describe(index: index, window: window))
        }
    }

    static func describe(index: Int?, window: NSWindow) -> String {
        let i = index.map { "[\($0)] " } ?? ""
        let occluded = !window.occlusionState.contains(.visible)
        return """
        \(i)id=\(window.windowNumber) title=\(window.title.debugDescription) \
        frame=\(NSStringFromRect(window.frame)) \
        content=\(NSStringFromRect(window.contentLayoutRect)) \
        visible=\(window.isVisible) key=\(window.isKeyWindow) main=\(window.isMainWindow) \
        occluded=\(occluded) backing=\(window.backingScaleFactor) \
        level=\(window.level.rawValue) alpha=\(window.alphaValue) \
        class=\(type(of: window))
        """
    }

    static func layoutIfChanged(_ view: NSView, reason: String) {
        let window = view.window
        let id = window?.windowNumber ?? view.hash
        let snapshot = """
        \(reason) bounds=\(NSStringFromRect(view.bounds)) \
        frame=\(NSStringFromRect(view.frame)) \
        window=\(window.map { describe(index: nil, window: $0) } ?? "nil")
        """
        if lastLayout[id] == snapshot { return }
        lastLayout[id] = snapshot
        GLBLog.event(GLBLog.window, snapshot)
    }

    private static func handle(_ note: Notification) {
        if let window = note.object as? NSWindow {
            GLBLog.event(
                GLBLog.window,
                "\(note.name.rawValue) \(describe(index: nil, window: window))"
            )
        } else {
            GLBLog.event(
                GLBLog.window,
                "\(note.name.rawValue) object=\(String(describing: note.object)) windows=\(NSApp.windows.count)"
            )
            if note.name == NSApplication.didFinishLaunchingNotification
                || note.name == NSApplication.willTerminateNotification
            {
                dumpWindows(note.name.rawValue)
            }
        }
    }
}
#endif
