import SwiftUI

public extension DS {
    /// Chrome animation. Every curve collapses to `nil` under Reduce Motion
    /// (HIG › Motion › "Accessibility"; read `@Environment(\.accessibilityReduceMotion)`).
    enum Motion {
        /// Default chrome duration (panes, clusters appearing).
        public static let chromeDuration: TimeInterval = 0.15
        /// Hover affordances (row eye buttons, focus fades).
        public static let hoverDuration: TimeInterval = 0.12

        /// `easeInOut` for chrome transitions, or `nil` when Reduce Motion is on.
        /// Successor of PreviewUI's `Animation.previewChrome(_:duration:)`.
        public static func chrome(
            reduceMotion: Bool,
            duration: TimeInterval = chromeDuration
        ) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: duration)
        }

        /// The quicker fade for hover-revealed controls, or `nil` when Reduce Motion is on.
        public static func hoverFade(reduceMotion: Bool) -> Animation? {
            chrome(reduceMotion: reduceMotion, duration: hoverDuration)
        }
    }
}
