import RealityKit
import SwiftUI

/// Host-only look hook. Quick Look leaves this `nil`.
@Observable
@MainActor
final class GLBPreviewHostSceneBridge {
    var lookRevision: Int = 0
    var backgroundColor = Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)
    var applyToContent: ((inout RealityViewCameraContent, Entity) -> Void)?

    func bump() {
        lookRevision += 1
    }
}
