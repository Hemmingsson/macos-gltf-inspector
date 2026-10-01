import DesignSystem
import SwiftUI

/// The camera lens chip and its popover: vertical field of view.
public struct FieldOfViewPopover<Viewport: ViewportController>: View {
    public var viewport: Viewport

    public var body: some View {
        DSGlassPopoverButton(
            "Field of view",
            systemImage: "camera.aperture",
            value: currentReading,
            help: "Field of view — \(currentReading)"
        ) {
            FieldOfViewControls(viewport: viewport)
        }
    }

    private var currentReading: String {
        PopoverControls.degreesReading(Double(viewport.fieldOfViewDegrees))
    }
}

public struct FieldOfViewControls<Viewport: ViewportController>: View {
    public var viewport: Viewport

    public var body: some View {
        DSPopoverPanel {
            if viewport.projection == .orthographic {
                DSButton("Use Perspective", variant: .prominent, size: .small) {
                    viewport.setProjection(.perspective)
                }
            } else {
                DSSlider(
                    "Field of View",
                    value: PopoverControls.fieldOfView(on: viewport),
                    in: PopoverControls.fieldOfViewRange,
                    step: 1,
                    reading: PopoverControls.degreesReading
                )

                HStack {
                    Spacer(minLength: DS.Spacing.m)
                    DSButton("Reset", size: .small) {
                        viewport.setFieldOfViewDegrees(Float(PopoverControls.defaultFieldOfViewDegrees))
                    }
                }
            }
        }
    }
}

// MARK: - Previews

private struct FieldOfViewControlsPreviewHost: View {
    var projection: Projection
    @State private var viewport: MockViewportController

    init(projection: Projection) {
        self.projection = projection
        _viewport = State(
            initialValue: MockViewportController(
                projection: projection,
                fieldOfViewDegrees: 45
            )
        )
    }

    var body: some View {
        PreviewCanvas(width: 260, background: .chrome) {
            FieldOfViewControls(viewport: viewport)
        }
    }
}

private struct FieldOfViewPopoverPreviewHost: View {
    var projection: Projection
    @State private var viewport: MockViewportController

    init(projection: Projection) {
        self.projection = projection
        _viewport = State(
            initialValue: MockViewportController(
                projection: projection,
                fieldOfViewDegrees: 45
            )
        )
    }

    var body: some View {
        PreviewCanvas(width: 400, height: 80, background: .canvas) {
            FieldOfViewPopover(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(DS.Spacing.xxl)
        }
    }
}

#Preview("controls perspective", traits: .fixedLayout(width: 260, height: 140)) {
    FieldOfViewControlsPreviewHost(projection: .perspective)
}

#Preview("controls orthographic", traits: .fixedLayout(width: 260, height: 100)) {
    FieldOfViewControlsPreviewHost(projection: .orthographic)
}

#Preview("popover perspective", traits: .fixedLayout(width: 400, height: 80)) {
    FieldOfViewPopoverPreviewHost(projection: .perspective)
}

#Preview("popover orthographic", traits: .fixedLayout(width: 400, height: 80)) {
    FieldOfViewPopoverPreviewHost(projection: .orthographic)
}
