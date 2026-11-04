import SwiftUI

/// A one-line status pill — "Valid glTF 2.0", "Checking validation…".
///
/// The status glyph takes the system colour (`DSStatus.tint`) and the badge the matching wash
/// (`DSStatus.fill`); the text stays `.primary` so it keeps full contrast on the tinted ground and
/// on glass. Fills its row's width. VoiceOver reads the title only — it already names the outcome.
/// For a status with details to expand, use `DSDisclosureCard`.
struct DSStatusBadge: View {
    private let title: String
    private let status: DSStatus
    private let systemImage: String?

    /// - Parameters:
    ///   - title: What the badge says ("Valid glTF 2.0").
    ///   - status: Colour and default symbol.
    ///   - systemImage: Overrides `status.systemImage`.
    init(_ title: String, status: DSStatus, systemImage: String? = nil) {
        self.title = title
        self.status = status
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            Image(systemName: systemImage ?? status.systemImage)
                .foregroundStyle(status.tint)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: 0)
        }
        .font(DS.Font.body.weight(.medium))
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .background(status.fill, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
