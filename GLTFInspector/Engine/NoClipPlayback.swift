import Foundation
import Observation
import PreviewUI

/// Transport for a canvas that cannot play clips: none listed, so the playback bar never shows.
@MainActor
@Observable
final class NoClipPlayback: ClipPlaybackController {
    var clips: [AnimationInfo] { [] }
    var activeClip: AnimationInfo? { nil }
    var isPlaying: Bool { false }
    var time: TimeInterval { 0 }
    var duration: TimeInterval { 0 }

    func play() {}
    func pause() {}
    func seek(_ time: TimeInterval) {}
    func select(_ clip: AnimationInfo) {}
    func advance(by delta: TimeInterval) {}
}
