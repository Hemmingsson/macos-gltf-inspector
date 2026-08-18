import Foundation
import os
import simd

/// Failures and rare framing/lighting notes. Do not add per-frame or load-path chatter —
/// that made Spacebar hitch.
enum GLBLog {
    static let subsystem = "com.laurie.GLBPreview"

    static let load = Logger(subsystem: subsystem, category: "load")
    static let preview = Logger(subsystem: subsystem, category: "preview")
    static let thumbnail = Logger(subsystem: subsystem, category: "thumbnail")
    static let prepare = Logger(subsystem: subsystem, category: "prepare")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let lighting = Logger(subsystem: subsystem, category: "lighting")
    static let host = Logger(subsystem: subsystem, category: "host")

    static func info(_ logger: Logger, _ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ logger: Logger, _ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func fmt3(_ v: SIMD3<Float>) -> String {
        String(format: "(%.4f,%.4f,%.4f)", v.x, v.y, v.z)
    }
}
