import DesignSystem
import SwiftUI

/// Runtime morph-target weight sliders (re-homed from the deleted host outliner).
///
/// Shown at file level whenever the host supplies targets — PreviewUI never imports RealityKit;
/// the host maps `PreviewMorph` ↔ `MorphTargetControl`.
public struct MorphWeightsSection: View {
    public var targets: [MorphTargetControl]
    public var onSetWeight: (String, Double) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSectionHeader("Morphs")
                .padding(.top, DS.Spacing.xl)
                .padding(.horizontal, DS.Spacing.l)
                .padding(.bottom, DS.Spacing.xs)

            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                ForEach(targets) { target in
                    DSSlider(
                        target.name,
                        value: Binding(
                            get: { target.weight },
                            set: { onSetWeight(target.id, $0) }
                        ),
                        in: 0...1,
                        step: 0.01
                    ) { String(format: "%.2f", $0) }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.bottom, DS.Spacing.l)
        }
    }
}

// MARK: - Previews

#Preview("1 target") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        MorphWeightsSection(
            targets: [MorphFixtures.triangleControls[0]],
            onSetWeight: { _, _ in }
        )
    }
}

#Preview("3 targets") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        MorphWeightsSection(
            targets: Array(MorphFixtures.faceControls.prefix(3)),
            onSetWeight: { _, _ in }
        )
    }
}
