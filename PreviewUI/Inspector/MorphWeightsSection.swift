import SwiftUI

/// Runtime morph-target weight sliders (re-homed from the deleted host outliner).
///
/// Shown at file level whenever the host supplies targets — PreviewUI never imports RealityKit;
/// the host maps `PreviewMorph` ↔ `MorphTargetControl`.
struct MorphWeightsSection: View {
    var targets: [MorphTargetControl]
    var onSetWeight: (String, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Morphs")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(targets) { target in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.name)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Slider(
                            value: Binding(
                                get: { target.weight },
                                set: { onSetWeight(target.id, $0) }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)
                        .accessibilityLabel("Morph \(target.name)")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }
}
