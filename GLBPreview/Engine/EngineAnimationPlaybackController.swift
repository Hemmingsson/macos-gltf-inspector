import Foundation
import Observation
import RealityKit

/// Live clip transport over RealityKit playback + `PreviewClip`.
///
/// `advance(by:)` mirrors the RealityKit playhead (`PlaybackBar` ticks; RK owns time).
@MainActor
@Observable
final class EngineAnimationPlaybackController: AnimationPlaybackController {
    private let entity: Entity
    private var previewClips: [PreviewClip]
    private var playback: RealityKit.AnimationPlaybackController?

    private(set) var clips: [AnimationInfo]
    private(set) var activeClip: AnimationInfo?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0

    var duration: TimeInterval { max(activeClip?.duration ?? 0, 0) }

    init(entity: Entity, clips: [PreviewClip]) {
        self.entity = entity
        self.previewClips = clips
        self.clips = clips.map {
            AnimationInfo(index: $0.id, name: $0.title, duration: $0.duration)
        }
        self.activeClip = self.clips.first
    }

    /// Convenience from a loaded model (usable RealityKit clips + document name fallback).
    convenience init(loaded: EntityLoader.LoadedModel) {
        let clips = PreviewClip.usable(on: loaded.entity, document: loaded.document)
        self.init(entity: loaded.entity, clips: clips)
    }

    func play() {
        guard !clips.isEmpty else { return }
        if playback == nil {
            startActiveClip(playing: true)
        } else {
            playback?.resume()
        }
        isPlaying = true
    }

    func pause() {
        playback?.pause()
        isPlaying = false
    }

    func seek(_ time: TimeInterval) {
        let span = max(duration, 0.001)
        let clamped = min(max(time, 0), span)
        self.time = duration > 0 ? clamped : 0
        playback?.time = self.time
    }

    func select(_ clip: AnimationInfo) {
        activeClip = clip
        time = 0
        startActiveClip(playing: isPlaying)
    }

    func advance(by _: TimeInterval) {
        guard isPlaying, let playback, duration > 0 else { return }
        time = playback.time.truncatingRemainder(dividingBy: duration)
    }

    private func startActiveClip(playing: Bool) {
        guard let activeClip,
              let preview = previewClips.first(where: { $0.id == activeClip.id.index })
        else {
            playback?.stop()
            playback = nil
            return
        }
        playback?.stop()
        time = 0
        playback = entity.playAnimation(preview.resource.repeat())
        if playing {
            playback?.resume()
        } else {
            playback?.pause()
        }
    }
}
