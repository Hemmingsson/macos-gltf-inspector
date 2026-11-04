import SwiftUI

/// One issue shown where it applies — a status glyph and a wrapping message on the status wash.
///
/// The inspector stacks these at the top of a selection that a validator finding is about, so
/// "Material requires a tangent space…" sits on the material it names rather than in a file-wide
/// list. `.warning` and `.error` read as faults; `.note` (info / hint) stays neutral so a tip never
/// looks like damage. For a status with many details to fold away, use `DSDisclosureCard`.
public struct DSInlineIssue: View {
    private let text: String
    private let status: DSStatus

    public init(_ text: String, status: DSStatus = .warning) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            Image(systemName: status.systemImage)
                .font(DS.Font.caption)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
            Text(text)
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background(status.fill, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(Self.spokenPrefix(status)) \(text)"))
    }

    private static func spokenPrefix(_ status: DSStatus) -> String {
        switch status {
        case .error: "Error:"
        case .warning: "Warning:"
        case .note: "Note:"
        case .valid, .pending: ""
        }
    }
}

// MARK: - Previews

#Preview("Inline issue") {
    DSContentPreviewStage {
        DSInlineIssue("Material requires a tangent space but the mesh primitive does not provide it.")
        DSInlineIssue("Image has non-power-of-two dimensions: 1024x576.", status: .note)
        DSInlineIssue("Mesh primitive is missing its POSITION attribute.", status: .error)
    }
}

#Preview("Inline issue long text, dark") {
    DSContentPreviewStage {
        DSInlineIssue(
            "Material requires a tangent space but the mesh primitive does not provide it. Runtime-generated tangent space may be non-portable across implementations."
        )
        DSInlineIssue("Image has non-power-of-two dimensions: 1024x576.", status: .note)
    }
    .preferredColorScheme(.dark)
}
