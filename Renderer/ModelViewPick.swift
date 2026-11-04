import AppKit

/// Click-vs-drag discrimination for canvas picking (view points, window space).
public enum ModelViewPick {
    public static let defaultClickThreshold: CGFloat = 3

    public static func isClick(start: NSPoint, end: NSPoint, threshold: CGFloat = defaultClickThreshold) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < threshold
    }
}

/// Paces hover picks: at most one every `minimumInterval` seconds, never while the camera is
/// busy (dragging, auto-rotating, easing onto a selection). The caller schedules the pick after
/// the returned delay, using the pointer's latest position, then reports `didPick`.
public struct HoverPickThrottle: Sendable, Equatable {
    public var minimumInterval: Double
    public private(set) var lastPickTime: Double?

    public init(minimumInterval: Double = 1.0 / 15) {
        self.minimumInterval = minimumInterval
    }

    /// Seconds to wait before picking (0 = now), or nil to skip this move.
    public func delay(at now: Double, isBusy: Bool) -> Double? {
        guard !isBusy else { return nil }
        guard let lastPickTime else { return 0 }
        return max(0, minimumInterval - (now - lastPickTime))
    }

    public mutating func didPick(at now: Double) {
        lastPickTime = now
    }
}
