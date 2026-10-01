import DesignSystem
import SwiftUI

/// "What our pipeline did" — silent import changes, so nothing is altered without a receipt.
public struct PipelineSection: View {
    public var report: PipelineReport

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.horizontal, DS.Spacing.l)
                .padding(.top, DS.Spacing.m)

            InspectorSectionHeader("This model, our pipeline", top: DS.Spacing.m)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                ForEach(report.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.s) {
                        Circle()
                            .fill(dotStyle(for: entry))
                            .frame(width: 6, height: 6)
                            .padding(.top, DS.Spacing.xs)
                        Text(entryLabel(entry))
                            .font(DS.Font.callout)
                            .foregroundStyle(DS.Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pipeline: \(report.entries.map { entryLabel($0) }.joined(separator: "; "))")
    }

    private func entryLabel(_ entry: PipelineReport.Entry) -> String {
        if entry.kind == .lighting, let detail = entry.detail {
            return detail
        }
        if let detail = entry.detail {
            return "\(entry.title) (\(detail))"
        }
        return entry.title
    }

    /// Conversion / dequant steps are "we did work" (role green); lighting is status (quiet).
    private func dotStyle(for entry: PipelineReport.Entry) -> AnyShapeStyle {
        entry.kind == .lighting
            ? AnyShapeStyle(DS.Color.textTertiary)
            : AnyShapeStyle(DS.Color.Role.animation)
    }
}

// MARK: - Previews

#Preview("studio") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        PipelineSection(report: FixtureSceneModel.cube.pipelineReport)
    }
}

#Preview("file-lights") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        PipelineSection(report: FixtureSceneModel.lights.pipelineReport)
    }
}

#Preview("conversion") {
    PreviewCanvas(width: DS.Metrics.inspectorWidth) {
        PipelineSection(
            report: PipelineReport(entries: [
                PipelineReport.Entry(kind: .conversion, title: "KHR_materials_clearcoat"),
                PipelineReport.Entry(kind: .conversion, title: "Dequantized accessors", detail: "12 buffers"),
                PipelineReport.Entry(
                    kind: .lighting,
                    title: "Studio environment",
                    detail: "Bundled IBL"
                )
            ])
        )
    }
}
