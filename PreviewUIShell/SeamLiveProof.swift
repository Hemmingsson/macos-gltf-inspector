import Foundation

/// Headless contract proof for A2: playback, screenshot, scene, variants.
enum SeamLiveProof {
    @MainActor
    static func failure() -> String? {
        let clips = [
            AnimationInfo(index: 0, name: "Idle", duration: 10),
            AnimationInfo(index: 1, name: "Flap", duration: 4),
        ]
        let playback = MockPlayback(clips: clips)
        playback.play()
        playback.advance(by: 0.5)
        playback.select(clips[1])
        playback.seek(1.25)
        playback.pause()
        guard playback.callLog == ["play()", "select(Flap)", "seek(1.25)", "pause()"] else {
            return "playback log \(playback.callLog)"
        }
        guard playback.activeClip?.name == "Flap", playback.time == 1.25, !playback.isPlaying else {
            return "playback state"
        }

        let viewport = MockViewport()
        viewport.screenshot()
        viewport.setScene(NodeID(kind: .scene, index: 1))
        viewport.setMaterialVariant(0)
        guard viewport.callLog.contains("screenshot()"),
              viewport.callLog.contains("setScene(scene:1)"),
              viewport.callLog.contains("setMaterialVariant(0)")
        else {
            return "viewport log \(viewport.callLog)"
        }
        return nil
    }
}
