import SwiftUI

/// glTF-validator badge. Clean fixtures stay a quiet green card; warnings expand in place.
public struct ValidationSection: View {
    public var validation: ValidationResult
    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if validation.status != .ready || !validation.isClean {
                InspectorSectionHeader(title: "Validation")
            }

            Group {
                if validation.status == .pending {
                    pendingBadge
                } else if validation.isClean {
                    cleanBadge
                } else {
                    warningCard
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, validation.isClean && validation.status == .ready ? 4 : 2)
            .padding(.bottom, 4)
        }
        .onAppear {
            // Warnings start open so an invalid file's problems are immediately readable.
            if !validation.isClean { isExpanded = true }
        }
    }

    private var pendingBadge: some View {
        HStack(spacing: 9) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text3)
            Text("Checking validation…")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.text2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking validation")
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
        StatusWarningCard(
            summaryTitle: summaryTitle,
            rows: validation.issues.map {
                StatusWarningCard.Row(id: $0.id, message: $0.message)
            },
            isExpanded: $isExpanded
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

    // Inline greens and ambers — Theme has no dedicated validation colour tokens.
    public static let validFill = Color.dynamic(
        light: .init(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 0.10),
        dark: .init(srgbRed: 52 / 255, green: 199 / 255, blue: 89 / 255, alpha: 0.18)
    )
    public static let validStroke = Color.dynamic(light: 0x2CA24A, dark: 0x30D158)
    public static let validText = Color.dynamic(light: 0x227A3A, dark: 0x6CE08A)
}

// MARK: - Previews

#Preview("pending", traits: .fixedLayout(width: Theme.sidebarWidth, height: 72)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 72) {
        ValidationSection(validation: ValidationFixtures.pending)
    }
}

#Preview("clean", traits: .fixedLayout(width: Theme.sidebarWidth, height: 56)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 56) {
        ValidationSection(validation: ValidationFixtures.clean)
    }
}

#Preview("warnings expanded", traits: .fixedLayout(width: Theme.sidebarWidth, height: 200)) {
    PreviewCanvas(width: Theme.sidebarWidth, height: 200) {
        ValidationSection(validation: ValidationFixtures.withErrors)
    }
}
