import DesignSystem
import SwiftUI

/// Shared bindings and readings for the Lighting and Field of View popovers.
@MainActor
enum PopoverControls {
    static let defaultFieldOfViewDegrees: Double = 35
    static let fieldOfViewRange: ClosedRange<Double> = 15...90

    static func lighting<Viewport: ViewportController, Value>(
        _ field: WritableKeyPath<LightingSettings, Value>,
        on viewport: Viewport
    ) -> Binding<Value> {
        Binding(
            get: { viewport.lighting[keyPath: field] },
            set: { newValue in
                var lighting = viewport.lighting
                lighting[keyPath: field] = newValue
                viewport.setLighting(lighting)
            }
        )
    }

    static func fieldOfView<Viewport: ViewportController>(
        on viewport: Viewport
    ) -> Binding<Double> {
        Binding(
            get: { Double(viewport.fieldOfViewDegrees) },
            set: { viewport.setFieldOfViewDegrees(Float($0)) }
        )
    }

    static func exposureReading(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " EV"
    }

    static func degreesReading(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + "°"
    }
}
