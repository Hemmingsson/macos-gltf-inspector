import SwiftUI

/// Quiet uppercase section label — SCENE, MATERIALS, FILE, TRANSFORM · AUTHORED.
///
/// Typography comes from `.dsSectionHeader()` (subheadline semibold, uppercased, tracked), in the
/// secondary colour. Carries the `.isHeader` accessibility trait so VoiceOver's heading rotor can
/// jump between sections.
///
/// No padding: the pane or `Section` that hosts it owns the rhythm around it.
struct DSSectionHeader: View {
    private let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .dsSectionHeader()
            .foregroundStyle(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
