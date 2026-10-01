import SwiftUI

/// An expandable status card — "2 warnings" that opens onto the list of issues.
///
/// A real `DisclosureGroup` (so expansion is a binding the caller owns and the content is only
/// built when open), styled by `DSDisclosureCardStyle`: status glyph + emphasised title, a
/// trailing chevron, the whole header one click target, the card washed in `DSStatus.fill`.
/// Expansion animates with `DS.Motion.chrome`, which is `nil` under Reduce Motion.
public struct DSDisclosureCard<Content: View>: View {
    private let title: String
    private let status: DSStatus
    @Binding private var isExpanded: Bool
    private let content: Content

    /// - Parameters:
    ///   - title: Summary shown in the header ("1 error · 2 warnings").
    ///   - status: Glyph, glyph colour and card wash.
    ///   - isExpanded: Expansion, owned by the caller.
    ///   - content: Shown under the header when expanded.
    public init(
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

    public var body: some View {
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
public struct DSDisclosureMessage: Identifiable, Hashable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public extension DSDisclosureCard where Content == DSDisclosureMessageList {
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
public struct DSDisclosureMessageList: View {
    private let status: DSStatus
    private let messages: [DSDisclosureMessage]

    public init(status: DSStatus, messages: [DSDisclosureMessage]) {
        self.status = status
        self.messages = messages
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(messages) { message in
                if message.id != messages.first?.id {
                    Divider()
                }
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                    Image(systemName: status.systemImage)
                        .font(DS.Font.caption)
                        .foregroundStyle(status.tint)
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
public struct DSDisclosureCardStyle: DisclosureGroupStyle {
    private let status: DSStatus

    public init(status: DSStatus) {
        self.status = status
    }

    public func makeBody(configuration: Configuration) -> some View {
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

// MARK: - Previews

private let previewMessages = [
    DSDisclosureMessage(id: "accessor", text: "Accessor min length must be a multiple of component size"),
    DSDisclosureMessage(id: "extension", text: "Unused extension KHR_materials_unlit"),
]

#Preview("Disclosure card") {
    @Previewable @State var warningsOpen = true
    @Previewable @State var errorsOpen = false
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSDisclosureCard("2 warnings", isExpanded: $warningsOpen, messages: previewMessages)
        DSDisclosureCard("1 error", status: .error, isExpanded: $errorsOpen, messages: [previewMessages[0]])
    }
}

#Preview("Disclosure card long text, empty, dark") {
    @Previewable @State var open = true
    @Previewable @State var emptyOpen = true
    DSContentPreviewStage(width: DS.Metrics.sidebarWidth) {
        DSDisclosureCard(
            "3 textures dropped · 2 extensions ignored by the RealityKit pipeline",
            isExpanded: $open,
            messages: previewMessages
        )
        DSDisclosureCard("No issues", status: .valid, isExpanded: $emptyOpen, messages: [])
    }
    .preferredColorScheme(.dark)
}
