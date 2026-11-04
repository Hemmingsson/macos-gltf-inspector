import SwiftUI

extension DS {
    /// Chrome animation. Every curve collapses to `nil` under Reduce Motion
    /// (HIG › Motion › "Accessibility"; read `@Environment(\.accessibilityReduceMotion)`).
    enum Motion {
        /// Default chrome duration (panes, clusters appearing).
        static let chromeDuration: TimeInterval = 0.15

        /// `easeInOut` for chrome transitions, or `nil` when Reduce Motion is on.
        static func chrome(
            reduceMotion: Bool,
            duration: TimeInterval = chromeDuration
        ) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: duration)
        }
    }
}
