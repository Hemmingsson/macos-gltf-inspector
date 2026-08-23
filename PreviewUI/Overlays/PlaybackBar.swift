import SwiftUI

/// Bottom-centre animation controls.
///
/// Shown only when `Availability.hasAnimations`. Transport lives on
/// `ClipPlaybackController` — the bar never owns a local clock.
public struct PlaybackBar<Playback: ClipPlaybackController>: View {
    public var playback: Playback

    @State private var isSeeking = false

    public var body: some View {
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
                    get: { playback.time },
                    set: { playback.seek($0) }
                ),
                in: 0...max(playback.duration, 0.001)
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
        .task(id: playback.isPlaying) {
            guard playback.isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !isSeeking else { continue }
                playback.advance(by: 0.05)
            }
        }
    }

    private var timeLabel: String {
        "\(formatTime(playback.time)) / \(formatTime(playback.duration))"
    }

    @ViewBuilder
    private var clipMenu: some View {
        if playback.clips.count > 1 {
            Menu {
                Picker("Animation clip", selection: clipBinding) {
                    ForEach(playback.clips) { clip in
                        Text(clip.name).tag(Optional(clip.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 5) {
                    Text(playback.activeClip?.name ?? "Clip")
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
            .accessibilityValue(playback.activeClip?.name ?? "")
        } else if let only = playback.activeClip ?? playback.clips.first {
            Text(only.name)
                .font(.system(size: 12))
                .foregroundStyle(Theme.glyph)
                .accessibilityLabel("Animation clip")
                .accessibilityValue(only.name)
        }
    }

    private var clipBinding: Binding<NodeID?> {
        Binding(
            get: { playback.activeClip?.id },
            set: { id in
                guard let id, let clip = playback.clips.first(where: { $0.id == id }) else { return }
                playback.select(clip)
            }
        )
    }

    private var playButton: some View {
        PlaybackPlayButton(isPlaying: playback.isPlaying) {
            if playback.isPlaying {
                playback.pause()
            } else {
                playback.play()
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Previews

private struct PlaybackBarPreviewHost: View {
    @State private var playback: MockPlaybackController

    init(isPlaying: Bool, time: TimeInterval) {
        _playback = State(
            initialValue: MockPlaybackController(isPlaying: isPlaying, time: time)
        )
    }

    var body: some View {
        PreviewCanvas(width: 400, height: 100, background: .canvas) {
            PlaybackBar(playback: playback)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(OverlayMetrics.inset)
        }
    }
}

#Preview("paused", traits: .fixedLayout(width: 400, height: 100)) {
    PlaybackBarPreviewHost(isPlaying: false, time: 0)
}

#Preview("playing", traits: .fixedLayout(width: 400, height: 100)) {
    PlaybackBarPreviewHost(isPlaying: true, time: 0.75)
}

#Preview("scrubbing", traits: .fixedLayout(width: 400, height: 100)) {
    PlaybackBarPreviewHost(isPlaying: false, time: 1.25)
}
