import SwiftUI

/// "What our pipeline did" — silent import changes, so nothing is altered without a receipt.
struct PipelineSection: View {
    var report: PipelineReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.hair
                .frame(height: Theme.hairlineWidth)
                .padding(.horizontal, 14)
                .padding(.top, 10)

            InspectorSectionHeader(title: "This model, our pipeline")

            VStack(alignment: .leading, spacing: 4) {
                ForEach(report.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(dotColor(for: entry))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(entryLabel(entry))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textValue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 12)
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

    /// Conversion / dequant steps are "we did work" (green); lighting is status (quiet).
    private func dotColor(for entry: PipelineReport.Entry) -> Color {
        entry.kind == .lighting ? Theme.text3 : Theme.animation
    }
}
