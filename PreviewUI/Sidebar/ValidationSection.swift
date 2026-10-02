import DesignSystem
import SwiftUI

/// glTF-validator badge. Clean fixtures stay a quiet green card; warnings expand in place.
struct ValidationSection: View {
    var validation: ValidationResult
    @State private var isExpanded: Bool = false

    var body: some View {
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
                        issueSummary(errors: validation.errorCount, warnings: validation.warningCount),
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
