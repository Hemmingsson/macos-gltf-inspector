import DesignSystem
import SwiftUI

/// Bottom-centre animation controls.
///
/// Shown only when `Availability.hasAnimations`. Transport lives on
/// `ClipPlaybackController` — the bar never owns a local clock. One `DSHUDCapsule` so the play
/// button is borderless inside the glass (no glass on glass).
struct PlaybackBar<Playback: ClipPlaybackController>: View {
    var playback: Playback

    @State private var isSeeking = false

    var body: some View {
        DSHUDCapsule(
            height: OverlayMetrics.playbackHeight,
            horizontalPadding: DS.Spacing.l,
            spacing: DS.Spacing.l
        ) {
            clipMenu

            DSGlassIslandDivider()

            playButton

            DSHUDSlider(
                value: Binding(
                    get: { playback.time },
                    set: { playback.seek($0) }
                ),
                in: 0...max(playback.duration, 0.001),
                accessibilityLabel: "Animation time"
            ) { isSeeking = $0 }
            .controlSize(.small)
            .frame(width: OverlayMetrics.scrubWidth)

            Text(timeLabel)
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Time")
                .accessibilityValue(timeLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback")
        .background {
            PlaybackTickDriver(
                isPlaying: playback.isPlaying,
                isSeeking: isSeeking,
                onAdvance: { playback.advance(by: $0) }
            )
        }
    }

    private var timeLabel: String {
        "\(formatTime(playback.time)) / \(formatTime(playback.duration))"
    }

    @ViewBuilder
    private var clipMenu: some View {
        if playback.clips.count > 1 {
            DSGlassMenuButton(
                "Animation clip",
                systemImage: "film",
                style: .titled(playback.activeClip?.name ?? "Clip")
            ) {
                DSInlineMenuPicker("Animation clip", selection: clipBinding) {
                    ForEach(playback.clips) { clip in
                        Text(clip.name).tag(Optional(clip.id))
                    }
                }
            }
        } else if let only = playback.activeClip ?? playback.clips.first {
            Text(only.name)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
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

/// Frame-synced transport ticks — elapsed wall time between display frames.
private struct PlaybackTickDriver: View {
    let isPlaying: Bool
    let isSeeking: Bool
    let onAdvance: (TimeInterval) -> Void

    @State private var lastDate: Date?

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            Color.clear
                .onChange(of: isPlaying) { _, _ in
                    lastDate = nil
                }
                .onChange(of: isSeeking) { _, seeking in
                    if seeking { lastDate = nil }
                }
                .onChange(of: timeline.date) { _, date in
                    guard !isSeeking else {
                        lastDate = date
                        return
                    }
                    if let lastDate {
                        let delta = date.timeIntervalSince(lastDate)
                        if delta > 0 {
                            onAdvance(delta)
                        }
                    }
                    lastDate = date
                }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
