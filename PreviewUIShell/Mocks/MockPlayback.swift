import Foundation
import Observation

/// Shell player. Owns clip transport so `PlaybackBar` never keeps a local clock.
@MainActor
@Observable
final class MockPlayback: AnimationPlaybackController {
    private(set) var clips: [AnimationInfo]
    private(set) var activeClip: AnimationInfo?
    private(set) var isPlaying = false
    private(set) var time: TimeInterval = 0
    private(set) var callLog: [String] = []

    var duration: TimeInterval { max(activeClip?.duration ?? 0, 0) }

    init(clips: [AnimationInfo] = []) {
        self.clips = clips
        self.activeClip = clips.first
    }

    func replaceClips(_ clips: [AnimationInfo]) {
        self.clips = clips
        if let activeClip, clips.contains(where: { $0.id == activeClip.id }) {
            return
        }
        activeClip = clips.first
        time = 0
        isPlaying = false
    }

    func play() {
        isPlaying = true
        record("play()")
    }

    func pause() {
        isPlaying = false
        record("pause()")
    }

    func seek(_ time: TimeInterval) {
        let span = duration
        self.time = span > 0 ? min(max(time, 0), span) : 0
        record("seek(\(String(format: "%.2f", self.time)))")
    }

    func select(_ clip: AnimationInfo) {
        activeClip = clip
        time = 0
        record("select(\(clip.name))")
    }

    /// Shell clock step — `PlaybackBar` calls this while playing so time lives on the controller.
    func advance(by delta: TimeInterval) {
        guard isPlaying, duration > 0 else { return }
        time = (time + delta).truncatingRemainder(dividingBy: duration)
    }

    private func record(_ call: String) {
        callLog.append(call)
    }
}
