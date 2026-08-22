import SwiftUI

/// Bottom-centre animation controls (`Main-html` playback bar).
///
/// Shown only when `Availability.hasAnimations`. Cribbed conceptually from
/// `Shared/PreviewPlaybackBar` — copied, not imported (PreviewUI must not depend on Shared/).
///
/// Shell playback is local UI state only: there is no renderer clock yet. The seam will later
/// drive these bindings from a real `AnimationPlaybackController`.
struct PlaybackBar: View {
    var clips: [AnimationInfo]

    @State private var isPlaying = false
    @State private var isSeeking = false
    @State private var currentTime: TimeInterval = 0
    @State private var clipIndex = 0

    var body: some View {
        OverlayChrome(
            height: OverlayMetrics.playbackHeight,
            cornerRadius: OverlayMetrics.playbackRadius,
            horizontalPadding: 14
        ) {
            clipMenu

            Theme.hair
                .frame(width: Theme.hairlineWidth, height: 20)
                .accessibilityHidden(true)

            playButton

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { seek(to: $0) }
                ),
                in: 0...max(clipDuration, 0.001)
            ) { editing in
                isSeeking = editing
            }
            .controlSize(.small)
            .tint(Theme.accent)
            .frame(width: OverlayMetrics.scrubWidth)
            .accessibilityLabel("Animation time")

            Text(timeLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Time")
                .accessibilityValue(timeLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback")
        .onChange(of: clips.map(\.id)) { _, _ in
            clipIndex = 0
            currentTime = 0
            isPlaying = false
        }
        .onChange(of: clipIndex) { _, _ in
            currentTime = 0
        }
        // Shell-only clock: advances while playing so the scrubber is live without an engine.
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !isSeeking, clipDuration > 0 else { continue }
                currentTime = (currentTime + 0.05).truncatingRemainder(dividingBy: clipDuration)
            }
        }
    }

    private var clipDuration: TimeInterval {
        guard clips.indices.contains(clipIndex) else { return 0 }
        return max(clips[clipIndex].duration, 0)
    }

    private var timeLabel: String {
        "\(formatTime(currentTime)) / \(formatTime(clipDuration))"
    }

    @ViewBuilder
    private var clipMenu: some View {
        if clips.count > 1 {
            Menu {
                Picker("Animation clip", selection: $clipIndex) {
                    ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                        Text(clip.name).tag(index)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 5) {
                    Text(clips[safe: clipIndex]?.name ?? "Clip")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.glyph)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.glyph)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Animation clip")
            .accessibilityLabel("Animation clip")
            .accessibilityValue(clips[safe: clipIndex]?.name ?? "")
        } else if let only = clips.first {
            Text(only.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.glyph)
                .accessibilityLabel("Animation clip")
                .accessibilityValue(only.name)
        }
    }

    private var playButton: some View {
        PlaybackPlayButton(isPlaying: isPlaying) {
            isPlaying.toggle()
        }
    }

    private func seek(to time: TimeInterval) {
        currentTime = min(max(time, 0), clipDuration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct PlaybackPlayButton: View {
    var isPlaying: Bool
    var action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
