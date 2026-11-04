import Renderer
import SwiftUI

/// Timeline transport wired to the document canvas controller.
struct AnimationTimelineHUD: View {
    @Bindable var canvas: ModelCanvasController

    var body: some View {
        if !canvas.showsAnimationTimeline { EmptyView() }
        else { timeline }
    }

    private var timeline: some View {
        DSTimeline(
            isPlaying: playBinding,
            time: timeBinding,
            loops: $canvas.loops,
            speed: $canvas.speed,
            duration: canvas.activePlaybackDuration,
            capsuleHeight: OverlayMetrics.timelineHeight,
            clipTitles: canvas.animationClips.enumerated().map { index, clip in
                clip.name?.isEmpty == false ? clip.name! : "Clip \(index + 1)"
            },
            selectedClipIndices: canvas.selectedClipIndices,
            defaultClipIndices: canvas.defaultSelectedAnimationClipIndices,
            onSelectClip: { canvas.selectAnimationClip(at: $0) },
            onScrubbingChanged: { canvas.isScrubbing = $0 }
        )
        .focusSection()
        .onKeyPress(.space) {
            guard canvas.activePlaybackDuration > 0 else { return .ignored }
            canvas.togglePlayback()
            return .handled
        }
    }

    private var playBinding: Binding<Bool> {
        Binding(
            get: { canvas.isPlaying },
            set: { wantsPlay in
                if wantsPlay { canvas.play() } else { canvas.pause() }
            }
        )
    }

    private var timeBinding: Binding<Float> {
        Binding(
            get: { canvas.time },
            set: { canvas.scrub(to: $0) }
        )
    }
}

extension ModelCanvasController {
    /// True when the file has at least one clip with a positive duration.
    var showsAnimationTimeline: Bool {
        animationClips.contains { $0.duration > 0 }
    }
}
