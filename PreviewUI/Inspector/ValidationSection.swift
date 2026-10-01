import DesignSystem
import SwiftUI

/// glTF-validator badge. Clean fixtures stay a quiet green card; warnings expand in place.
public struct ValidationSection: View {
    public var validation: ValidationResult
    @State private var isExpanded: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if validation.status != .ready || !validation.isClean {
                InspectorSectionHeader("Validation", top: DS.Spacing.m)
            }

            Group {
                if validation.status == .pending {
                    DSStatusBadge("Checking validation…", status: .pending)
                } else if validation.isClean {
                    DSStatusBadge("Valid \(validation.formatLabel)", status: .valid)
                } else {
                    DSDisclosureCard(
                        summaryTitle,
                        status: validation.errorCount > 0 ? .error : .warning,
                        isExpanded: $isExpanded,
                        messages: validation.issues.map {
                            DSDisclosureMessage(id: $0.id, text: $0.message)
                        }
                    )
                }
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.top, validation.isClean && validation.status == .ready ? DS.Spacing.xs : DS.Spacing.xxs)
            .padding(.bottom, DS.Spacing.xs)
        }
        .onAppear {
            // Warnings start open so an invalid file's problems are immediately readable.
            if !validation.isClean { isExpanded = true }
        }
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
}

// MARK: - Previews

#Preview("pending", traits: .fixedLayout(width: 248, height: 72)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 72) {
        ValidationSection(validation: ValidationFixtures.pending)
    }
}

#Preview("clean", traits: .fixedLayout(width: 248, height: 56)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 56) {
        ValidationSection(validation: ValidationFixtures.clean)
    }
}

#Preview("warnings expanded", traits: .fixedLayout(width: 248, height: 200)) {
    PreviewCanvas(width: DS.Metrics.sidebarWidth, height: 200) {
        ValidationSection(validation: ValidationFixtures.withErrors)
    }
}
