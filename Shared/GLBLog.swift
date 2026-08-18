import Foundation
import os
import RealityKit
#if canImport(AppKit)
import AppKit
#endif

/// Failures go to Unified Logging. Info `event` is a no-op so call-site strings
/// (`describe`, URL stats) are not built — file/`print` logging made Spacebar hitch.
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

    static func event(
        _: Logger,
        _: @autoclosure () -> String,
        file _: String = #fileID,
        function _: String = #function,
        line _: Int = #line
    ) {}

    /// Info that must reach Unified Logging (framing/lighting verification).
    static func info(
        _ logger: Logger,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        logger.info("\(file, privacy: .public):\(line) \(function, privacy: .public) | \(message, privacy: .public)")
    }

    static func error(
        _ logger: Logger,
        _ message: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        logger.error("\(file, privacy: .public):\(line) \(function, privacy: .public) | \(message, privacy: .public)")
    }

    static func timed<T>(
        _: Logger,
        _: String,
        file _: String = #fileID,
        function _: String = #function,
        line _: Int = #line,
        _ work: () throws -> T
    ) rethrows -> T {
        try work()
    }

    static func timedAsync<T>(
        _: Logger,
        _: String,
        file _: String = #fileID,
        function _: String = #function,
        line _: Int = #line,
        _ work: () async throws -> T
    ) async rethrows -> T {
        try await work()
    }

    static func processBanner(_: String) {}

    @MainActor
    static func describe(_ entity: Entity) -> String {
        "\(entity.name) anims=\(entity.availableAnimations.count)"
    }

    static func describeURL(_ url: URL) -> String { url.path }

    static func fmt3(_ v: SIMD3<Float>) -> String {
        String(format: "(%.4f,%.4f,%.4f)", v.x, v.y, v.z)
    }
}

#if canImport(AppKit)
enum GLBWindowLog {
    static func start() {}
    static func dumpWindows(_: String) {}
    static func describe(index: Int?, window: NSWindow) -> String {
        _ = (index, window)
        return ""
    }
    static func layoutIfChanged(_: NSView, reason _: String) {}
}
#endif
