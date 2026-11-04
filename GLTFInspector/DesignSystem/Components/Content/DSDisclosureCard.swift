import SwiftUI

/// An expandable status card — "2 warnings" that opens onto the list of issues.
///
/// A real `DisclosureGroup` (so expansion is a binding the caller owns and the content is only
/// built when open), styled by `DSDisclosureCardStyle`: status glyph + emphasised title, a
/// trailing chevron, the whole header one click target, the card washed in `DSStatus.fill`.
/// Expansion animates with `DS.Motion.chrome`, which is `nil` under Reduce Motion.
struct DSDisclosureCard<Content: View>: View {
    private let title: String
    private let status: DSStatus
    @Binding private var isExpanded: Bool
    private let content: Content

    /// - Parameters:
    ///   - title: Summary shown in the header ("1 error · 2 warnings").
    ///   - status: Glyph, glyph colour and card wash.
    ///   - isExpanded: Expansion, owned by the caller.
    ///   - content: Shown under the header when expanded.
    init(
        _ title: String,
        status: DSStatus = .warning,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.status = status
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            HStack(spacing: DS.Spacing.m) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.bodyEmphasized)
                    .foregroundStyle(DS.Color.textPrimary)
            }
        }
        .disclosureGroupStyle(DSDisclosureCardStyle(status: status))
    }
}

/// One issue inside a `DSDisclosureCard`.
struct DSDisclosureMessage: Identifiable, Hashable, Sendable {
    var id: String
    var text: String
    /// Glyph and tint for this row. Nil takes the card's own status, so a card that mixes
    /// warnings with notes can still tell them apart.
    var status: DSStatus?

    init(id: String, text: String, status: DSStatus? = nil) {
        self.id = id
        self.text = text
        self.status = status
    }
}

extension DSDisclosureCard where Content == DSDisclosureMessageList {
    /// The common case: a list of issue messages, each with the status glyph, separated by
    /// hairlines.
    init(
        _ title: String,
        status: DSStatus = .warning,
        isExpanded: Binding<Bool>,
        messages: [DSDisclosureMessage]
    ) {
        self.init(title, status: status, isExpanded: isExpanded) {
            DSDisclosureMessageList(status: status, messages: messages)
        }
    }
}

/// Issue rows for `DSDisclosureCard(_:status:isExpanded:messages:)`: small status glyph, wrapping
/// `.primary` callout text, hairline `Divider`s between rows.
struct DSDisclosureMessageList: View {
    private let status: DSStatus
    private let messages: [DSDisclosureMessage]

    init(status: DSStatus, messages: [DSDisclosureMessage]) {
        self.status = status
        self.messages = messages
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(messages) { message in
                if message.id != messages.first?.id {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                    Image(systemName: (message.status ?? status).systemImage)
                        .font(DS.Font.caption)
                        .foregroundStyle((message.status ?? status).tint)
                        .accessibilityHidden(true)
                    Text(message.text)
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Spacing.m)
            }
        }
    }
}

/// `DisclosureGroup` as a status card. See `DSDisclosureCard`.
struct DSDisclosureCardStyle: DisclosureGroupStyle {
    private let status: DSStatus

    init(status: DSStatus) {
        self.status = status
    }

    func makeBody(configuration: Configuration) -> some View {
        DSDisclosureCardBody(configuration: configuration, status: status)
    }
}

/// Separate view so the style can read Reduce Motion from the environment.
private struct DSDisclosureCardBody: View {
    let configuration: DisclosureGroupStyleConfiguration
    let status: DSStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                withAnimation(DS.Motion.chrome(reduceMotion: reduceMotion)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Spacing.m) {
                    configuration.label
                    Spacer(minLength: DS.Spacing.m)
                    Image(systemName: "chevron.down")
                        .font(DS.Font.caption.weight(.semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(configuration.isExpanded ? "Collapse details" : "Expand details")

            if configuration.isExpanded {
                configuration.content
            }
        }
        .padding(.horizontal, DS.Spacing.l)
        .padding(.vertical, DS.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(status.fill, in: RoundedRectangle(cornerRadius: DS.Radius.medium, style: .continuous))
    }
}
