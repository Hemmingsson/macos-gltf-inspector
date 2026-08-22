import Foundation
import os

/// Failures and rare framing/lighting notes. Do not add per-frame or load-path chatter —
/// that made Spacebar hitch. Messages log `.public`, so keep them to diagnostics and file
/// *names* (`lastPathComponent`) — never full paths or file contents; the unified log is
/// world-readable.
enum AppLog {
    static let subsystem = "lol.mattias.gltf-inspector"

    static let load = Logger(subsystem: subsystem, category: "load")
    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let prepare = Logger(subsystem: subsystem, category: "prepare")
    static let lighting = Logger(subsystem: subsystem, category: "lighting")
    static let host = Logger(subsystem: subsystem, category: "host")

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
