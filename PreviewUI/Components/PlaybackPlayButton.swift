import SwiftUI

/// Transport play / pause control used by the playback bar overlay.
public struct PlaybackPlayButton: View {
    public var isPlaying: Bool
    public var action: () -> Void

    @FocusState private var isFocused: Bool

    public init(isPlaying: Bool, action: @escaping () -> Void) {
        self.isPlaying = isPlaying
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isPlaying ? Theme.onGlyph : Theme.glyph)
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .previewGlassButtonStyle(prominent: isPlaying)
        .focused($isFocused)
        .overlay {
            PreviewFocusStroke(shape: .roundedRect(8), isFocusedOverride: isFocused)
        }
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

// MARK: - Previews

#Preview("paused") {
    PlaybackPlayButton(isPlaying: false) {}
        .padding(24)
}

#Preview("playing") {
    PlaybackPlayButton(isPlaying: true) {}
        .padding(24)
}
