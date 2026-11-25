import AppKit

/// Trackpad haptics, in one place so every control taps the same way.
///
/// `NSHapticFeedbackManager` rather than SwiftUI's `sensoryFeedback`: on macOS the performer is
/// explicit about the pattern, and `.levelChange` is the firmest of the three the system offers
/// (`.generic` and `.alignment` are both lighter). Nothing happens on a Mac without a Force Touch
/// trackpad, or when the person has turned haptic feedback off in Trackpad settings — the API is
/// silent rather than failing, so callers need no check.
@MainActor
enum DSHaptics {
    /// One notch, for crossing a detent on a slider or landing on a new choice.
    static func detent() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
