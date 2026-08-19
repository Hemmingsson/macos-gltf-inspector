import Foundation
import os

/// Failures and rare framing/lighting notes. Do not add per-frame or load-path chatter —
/// that made Spacebar hitch.
enum GLBLog {
    static let subsystem = "com.laurie.GLBPreview"

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
