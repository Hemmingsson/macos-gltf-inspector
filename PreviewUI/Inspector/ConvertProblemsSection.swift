import SwiftUI

/// Convert losses next to Khronos validation — “not rendered as authored”.
struct ConvertProblemsSection: View {
    var problems: ConvertProblemList
    @State private var isExpanded: Bool = false

    var body: some View {
        if !problems.isEmpty {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorSectionHeader(title: "Not rendered as authored")

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ValidationSection.warnStroke)
                        Text(summaryTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(ValidationSection.warnText)
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ValidationSection.warnText.opacity(0.7))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(summaryTitle)
                .accessibilityHint(isExpanded ? "Collapse problems" : "Expand problems")

                if isExpanded {
                    ForEach(Array(problems.entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 12))
                                .foregroundStyle(ValidationSection.warnStroke)
                                .padding(.top, 1)
                            Text(entry.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            if index < problems.entries.count - 1 {
                                Theme.hair.frame(height: Theme.hairlineWidth)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ValidationSection.warnFill)
            )
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
        .onAppear {
            if problems.errorCount > 0 { isExpanded = true }
        }
    }

    private var summaryTitle: String {
        let errors = problems.errorCount
        let warnings = problems.warningCount
        if errors > 0 && warnings > 0 {
            return "\(errors) errors · \(warnings) warnings"
        }
        if errors > 0 {
            return errors == 1 ? "1 error" : "\(errors) errors"
        }
        return warnings == 1 ? "1 warning" : "\(warnings) warnings"
    }
}
