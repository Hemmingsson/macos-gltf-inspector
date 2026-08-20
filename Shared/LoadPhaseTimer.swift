import Foundation

/// Bench-only load-phase accumulator. Enabled from `LoadTimeBenchTests` via
/// `TaskLocal`. Production Quick Look / thumbnail paths leave `sink` nil.
enum LoadPhaseTimer {
    /// Keys match reserved bench JSON fields (including unused `gpu_upload_ms`).
    enum Phase: String, CaseIterable {
        case fileRead = "file_read_ms"
        case parse = "parse_ms"
        case decode = "decode_ms"
        case texture = "texture_ms"
        case sceneBuild = "scene_build_ms"
        case gpuUpload = "gpu_upload_ms"
    }

    final class Sink: @unchecked Sendable {
        private var totals: [Phase: Double] = [:]
        private let lock = NSLock()

        func add(_ phase: Phase, ms: Double) {
            lock.lock()
            totals[phase, default: 0] += ms
            lock.unlock()
        }

        func snapshot() -> [String: Double] {
            lock.lock()
            defer { lock.unlock() }
            return Dictionary(uniqueKeysWithValues: totals.map { ($0.key.rawValue, $0.value) })
        }
    }

    @TaskLocal static var sink: Sink?

    static func milliseconds(from start: ContinuousClock.Instant) -> Double {
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
    }

    /// No-op when `sink` is nil (QL / thumbnail) — does not sample the clock.
    static func measure<T>(_ phase: Phase, _ body: () throws -> T) rethrows -> T {
        guard let sink else { return try body() }
        let start = ContinuousClock.now
        defer { sink.add(phase, ms: milliseconds(from: start)) }
        return try body()
    }

    static func measure<T>(_ phase: Phase, _ body: () -> T) -> T {
        guard let sink else { return body() }
        let start = ContinuousClock.now
        defer { sink.add(phase, ms: milliseconds(from: start)) }
        return body()
    }
}
