import Foundation
import os

/// Failures and rare framing/lighting notes. Do not add per-frame or load-path chatter —
/// that made Spacebar hitch. Messages log `.public`, so keep them to diagnostics and file
/// *names* (`lastPathComponent`) — never full paths or file contents; the unified log is
/// world-readable.
///
/// When `GLTF_LOG_FILE` is set (dev.sh / launch.json), messages mirror to that file so agents
/// can read `.build/logs/debug.log` without `log stream`.
enum AppLog {
    static let subsystem = "lol.mattias.gltf-inspector"

    static let load = Logger(subsystem: subsystem, category: "load")
    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let prepare = Logger(subsystem: subsystem, category: "prepare")
    static let lighting = Logger(subsystem: subsystem, category: "lighting")
    static let host = Logger(subsystem: subsystem, category: "host")
    /// WebGL thumbnail spike. Remove with the spike if it does not ship.
    static let webThumb = Logger(subsystem: subsystem, category: "webthumb")

    private static let fileLock = NSLock()
    private static var logFilePath: String?

    /// Truncates and opens `GLTF_LOG_FILE` when set. Safe to call more than once.
    static func configureFileSink() {
        guard let path = ProcessInfo.processInfo.environment["GLTF_LOG_FILE"], !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        fileLock.lock()
        logFilePath = path
        fileLock.unlock()

        let stamp = ISO8601DateFormatter().string(from: Date())
        appendToFile("[\(stamp)] [INFO] --- session start ---\n")
    }

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
        mirrorToFile(level: "INFO", message: message)
    }

    static func error(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
        mirrorToFile(level: "ERROR", message: message)
    }

    private static func mirrorToFile(level: String, message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        appendToFile("[\(stamp)] [\(level)] \(message)\n")
    }

    private static func appendToFile(_ line: String) {
        fileLock.lock()
        defer { fileLock.unlock() }
        guard let path = logFilePath, let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: path) {
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
