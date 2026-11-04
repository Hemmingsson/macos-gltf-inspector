import SwiftUI

/// Accessibility-only signal that a document window's canvas shows the model, for UI tests
/// (`GLTFInspectorUITests`): an element `canvas-ready` exists only while the canvas has content.
/// Nothing is drawn.
extension View {
    func canvasReadyMarker(isReady: Bool) -> some View {
        overlay(alignment: .topLeading) {
            if isReady {
                Color.clear
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("canvas-ready")
            }
        }
    }
}
