import SwiftUI

/// Quiet uppercase section label — SCENE, MATERIALS, FILE, TRANSFORM · AUTHORED.
///
/// Typography comes from `.dsSectionHeader()` (subheadline semibold, uppercased, tracked). The
/// colour is hierarchical: `.secondary` by default, as in the approved mockup; `.tertiary` for a
/// header that must recede further (e.g. above a single quiet row). Carries the `.isHeader`
/// accessibility trait so VoiceOver's heading rotor can jump between sections.
///
/// No padding: the pane or `Section` that hosts it owns the rhythm around it.
public struct DSSectionHeader: View {
    /// How far the header recedes.
    public enum Tone: Sendable {
        case secondary
        case tertiary
    }

    private let title: String
    private let tone: Tone

    public init(_ title: String, tone: Tone = .secondary) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Text(title)
            .dsSectionHeader()
            .foregroundStyle(tone == .secondary ? DS.Color.textSecondary : DS.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews

#Preview("Section header") {
    DSContentPreviewStage {
        DSSectionHeader("Scene")
        DSSectionHeader("Transform · authored")
        DSSectionHeader("Materials", tone: .tertiary)
        DSSectionHeader("This model, our pipeline — extensions we ignored and textures we dropped")
    }
}

#Preview("Section header, dark") {
    DSContentPreviewStage {
        DSSectionHeader("Geometry")
        DSSectionHeader("File", tone: .tertiary)
    }
    .preferredColorScheme(.dark)
}
