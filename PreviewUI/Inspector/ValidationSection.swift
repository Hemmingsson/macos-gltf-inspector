import SwiftUI

/// glTF-validator badge. Clean fixtures stay a quiet green card; warnings expand in place.
struct ValidationSection: View {
    var validation: ValidationResult
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title only when we have something to expand into — the clean badge is
            // self-describing ("Valid glTF 2.0") and Main-html omits the header for it.
            if !validation.isClean {
                InspectorSectionHeader(title: "Validation")
            }

            Group {
                if validation.isClean {
                    cleanBadge
                } else {
                    warningCard
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, validation.isClean ? 4 : 2)
            .padding(.bottom, 4)
        }
        .onAppear {
            // Warnings start open so Slice 6's invalid fixture is immediately readable.
            if !validation.isClean { isExpanded = true }
        }
    }

    private var cleanBadge: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Self.validStroke)
            Text("Valid \(validation.formatLabel)")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Self.validText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Self.validFill)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Valid \(validation.formatLabel)")
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Self.warnStroke)
                    Text(summaryTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Self.warnText)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Self.warnText.opacity(0.7))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryTitle)
            .accessibilityHint(isExpanded ? "Collapse warnings" : "Expand warnings")

            if isExpanded {
                ForEach(Array(validation.issues.enumerated()), id: \.element.id) { index, issue in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(Self.warnStroke)
                            .padding(.top, 1)
                        Text(issue.message)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        if index < validation.issues.count - 1 {
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
                .fill(Self.warnFill)
        )
    }

    private var summaryTitle: String {
        let errors = validation.errorCount
        let warnings = validation.warningCount
        if errors > 0 && warnings > 0 {
            return "\(errors) errors · \(warnings) warnings"
        }
        if errors > 0 {
            return errors == 1 ? "1 error" : "\(errors) errors"
        }
        return warnings == 1 ? "1 warning" : "\(warnings) warnings"
    }

    // Main-html / Inspect-html inline greens and ambers — Theme has no validation tokens yet
    // (and Theme.swift is owned by another slice).
    private static let validFill = Color.dynamic(
        light: .init(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 0.10),
        dark: .init(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 0.18)
    )
    private static let validStroke = Color.dynamic(light: 0x2CA24A, dark: 0x30D158)
    private static let validText = Color.dynamic(light: 0x227A3A, dark: 0x6CE08A)

    private static let warnFill = Color.dynamic(
        light: .init(srgbRed: 245 / 255, green: 166 / 255, blue: 35 / 255, alpha: 0.10),
        dark: .init(srgbRed: 245 / 255, green: 166 / 255, blue: 35 / 255, alpha: 0.18)
    )
    private static let warnStroke = Color.dynamic(light: 0xD6902A, dark: 0xFFC04D)
    private static let warnText = Color.dynamic(light: 0xA86C1A, dark: 0xFFC04D)
}
