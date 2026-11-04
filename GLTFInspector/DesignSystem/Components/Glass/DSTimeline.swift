import AppKit
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
    let capsuleHeight: CGFloat
    let clipTitles: [String]
    let selectedClipIndices: [Int]
    let defaultClipIndices: [Int]
    var onSelectClip: (Int?) -> Void
    var onScrubbingChanged: (Bool) -> Void = { _ in }

    private static let speedChoices: [Float] = [0.25, 0.5, 1, 1.5, 2]
    private static let frameStep: Float = 1 / 30
    private static let largeStep: Float = 1

    var body: some View {
        DSHUDCapsule(height: capsuleHeight, horizontalPadding: DS.Spacing.m, spacing: DS.Spacing.s) {
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
            in: 0 ... max(duration, 0.001)
        ) {
            Text("Timeline")
        } minimumValueLabel: {
            Text(PlaybackTimeFormat.string(time))
        } maximumValueLabel: {
            Text(PlaybackTimeFormat.string(duration))
        } onEditingChanged: { editing in
            onScrubbingChanged(editing)
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Timeline")
        .accessibilityValue("\(PlaybackTimeFormat.string(time)) of \(PlaybackTimeFormat.string(duration))")
        .accessibilityAdjustableAction { direction in
            let step = Self.scrubStep(large: NSEvent.modifierFlags.contains(.option))
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
            time = min(time + Self.frameStep, max(duration, 0.001))
        }
    }

    private static func scrubStep(large: Bool) -> Float {
        large ? largeStep : frameStep
    }

    private var clipPicker: some View {
        DSGlassMenuButton("Animation clip", systemImage: "stopwatch", style: .text(clipPickerTitle), isEngaged: isSingleClipSelected) {
            Button {
                onSelectClip(nil)
            } label: {
                clipMenuRow(title: "Default", isChecked: selectedClipIndices == defaultClipIndices)
            }
            Divider()
            ForEach(Array(clipTitles.enumerated()), id: \.offset) { index, title in
                Button {
                    onSelectClip(index)
                } label: {
                    clipMenuRow(title: title, isChecked: selectedClipIndices == [index])
                }
            }
        }
    }

    private func clipMenuRow(title: String, isChecked: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: DS.Spacing.m)
            if isChecked {
                Image(systemName: "checkmark")
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
            return "Default"
        }
        if selectedClipIndices.count == 1, let index = selectedClipIndices.first, clipTitles.indices.contains(index) {
            return clipTitles[index]
        }
        return "Default"
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
