import DesignSystem
import SwiftUI

/// Transport play / pause control used by the playback bar overlay.
///
/// A `DSGlassIconButton`. Inside `DSHUDCapsule` it is `inIsland` (borderless, no glass of its
/// own). Standalone previews draw one glass layer.
struct PlaybackPlayButton: View {
    var isPlaying: Bool
    var action: () -> Void

    var body: some View {
        DSGlassIconButton(
            isPlaying ? "Pause" : "Play",
            systemImage: isPlaying ? "pause.fill" : "play.fill",
            isEngaged: isPlaying,
            action: action
        )
    }
}

// MARK: - Previews

#Preview("paused") {
    PlaybackPlayButton(isPlaying: false) {}
        .padding(DS.Spacing.xxl)
}

#Preview("playing") {
    PlaybackPlayButton(isPlaying: true) {}
        .padding(DS.Spacing.xxl)
}
