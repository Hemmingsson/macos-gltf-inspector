import Renderer
import SwiftUI

/// Canvas-bottom animation transport: play/pause, scrubber, clip picker, loop, and speed.
///
/// Drawn as one `DSHUDCapsule` island. The scrubber uses a system slider; other controls are
/// DS glass buttons from the same family as the toolbar clusters.
struct DSTimeline: View {
    @Binding var isPlaying: Bool
    @Binding var time: Float
    @Binding var loops: Bool
    @Binding var speed: Float
    let duration: Float
    let clips: [AnimationClipDescriptor]
    let selectedClipIndices: [Int]
    let defaultClipIndices: [Int]
    var onSelectClip: (Int?) -> Void

    private static let speedChoices: [Float] = [0.25, 0.5, 1, 1.5, 2]

    var body: some View {
        DSHUDCapsule(height: OverlayMetrics.timelineHeight, horizontalPadding: DS.Spacing.m, spacing: DS.Spacing.s) {
            playPauseButton
            DSGlassIslandDivider()
            timeReadout
            scrubber
            durationReadout
            DSGlassIslandDivider()
            clipPicker
            DSGlassIslandDivider()
            DSGlassToggleButton("Loop", systemImage: "repeat", isOn: $loops)
            DSGlassIslandDivider()
            speedMenu
        }
        .frame(minWidth: 320, maxWidth: 520)
    }

    private var playPauseButton: some View {
        Button {
            isPlaying.toggle()
        } label: {
            Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                .labelStyle(.iconOnly)
                .dsGlassControlLabel(.circle, isHighlighted: isPlaying)
        }
        .buttonStyle(.plain)
        .dsGlassControlSurface(isEngaged: isPlaying)
        .help(isPlaying ? "Pause" : "Play")
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityAction(named: "Toggle playback") { isPlaying.toggle() }
    }

    private var timeReadout: some View {
        Text(PlaybackTimeFormat.string(time))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var durationReadout: some View {
        Text(PlaybackTimeFormat.string(duration))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var scrubber: some View {
        Slider(
            value: $time,
            in: 0 ... max(duration, 0.001),
            step: 0.01
        ) {
            Text("Timeline")
        } minimumValueLabel: {
            Text(PlaybackTimeFormat.string(time))
        } maximumValueLabel: {
            Text(PlaybackTimeFormat.string(duration))
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(PlaybackTimeFormat.string(time)) of \(PlaybackTimeFormat.string(duration))")
        .accessibilityAdjustableAction { direction in
            let step = max(duration * 0.01, 0.001)
            switch direction {
            case .increment:
                time = min(time + step, max(duration, 0.001))
            case .decrement:
                time = max(time - step, 0)
            @unknown default:
                break
            }
        }
        .accessibilityAction(named: "Step timeline forward") {
            let step = max(duration * 0.01, 0.001)
            time = min(time + step, max(duration, 0.001))
        }
    }

    private var clipPicker: some View {
        DSGlassMenuButton("Animation clip", systemImage: "stopwatch", style: .text(clipPickerTitle), isEngaged: isSingleClipSelected) {
            Button("All") {
                onSelectClip(nil)
            }
            Divider()
            ForEach(Array(clips.enumerated()), id: \.offset) { index, clip in
                Button(clipLabel(clip, index: index)) {
                    onSelectClip(index)
                }
            }
        }
    }

    private var speedMenu: some View {
        DSGlassMenuButton("Speed", systemImage: "gauge.with.dots.needle.67percent", style: .text(speedLabel), isEngaged: speed != 1) {
            ForEach(Self.speedChoices, id: \.self) { choice in
                Button(speedChoiceLabel(choice)) {
                    speed = choice
                }
            }
        }
    }

    private var isSingleClipSelected: Bool {
        selectedClipIndices != defaultClipIndices && selectedClipIndices.count == 1
    }

    private var clipPickerTitle: String {
        if selectedClipIndices == defaultClipIndices {
            return "All"
        }
        if selectedClipIndices.count == 1, let index = selectedClipIndices.first, clips.indices.contains(index) {
            return clipLabel(clips[index], index: index)
        }
        return "All"
    }

    private func clipLabel(_ clip: AnimationClipDescriptor, index: Int) -> String {
        clip.name?.isEmpty == false ? clip.name! : "Clip \(index + 1)"
    }

    private var speedLabel: String {
        speedChoiceLabel(speed)
    }

    private func speedChoiceLabel(_ value: Float) -> String {
        value == 1 ? "1×" : String(format: "%.2g×", value)
    }
}

enum PlaybackTimeFormat {
    /// `mm:ss.ff` for HUD readouts and accessibility.
    static func string(_ seconds: Float) -> String {
        let centiseconds = max(0, Int((Double(seconds) * 100).rounded()))
        let cs = centiseconds % 100
        let totalSeconds = centiseconds / 100
        let s = totalSeconds % 60
        let m = totalSeconds / 60
        return String(format: "%02d:%02d.%02d", m, s, cs)
    }
}
