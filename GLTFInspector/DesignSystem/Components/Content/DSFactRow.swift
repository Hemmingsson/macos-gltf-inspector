import SwiftUI

/// A read-only "label · value" fact: Triangles 12, File size 2 KB, Used by Cube, Sphere.
///
/// A `LabeledContent` styled with `DSFactLabeledContentStyle`, so it keeps the system's label /
/// value semantics (VoiceOver reads "Triangles, 12" as one element). The value is selectable
/// text, so a count or name can be copied.
struct DSFactRow<Value: View>: View {
    private let label: String
    private let value: Value

    /// Custom value view (a swatch plus text, say). It still gets the value typography.
    init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    var body: some View {
        LabeledContent {
            value
        } label: {
            Text(label)
        }
        .labeledContentStyle(.dsFact)
    }
}

extension DSFactRow where Value == Text {
    /// Text value.
    init(_ label: String, value: String) {
        self.init(label) { Text(value) }
    }
}

/// `LabeledContent` as a fact row: label leading in `.secondary` callout, value trailing in
/// `.primary` monospaced-digit callout (`Font.callout.monospacedDigit()`), selectable, wrapping trailing-aligned
/// when long.
struct DSFactLabeledContentStyle: LabeledContentStyle {
    init() {}

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            configuration.label
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: DS.Spacing.m)
            configuration.content
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

extension LabeledContentStyle where Self == DSFactLabeledContentStyle {
    /// The design system's fact-row style. See `DSFactLabeledContentStyle`.
    static var dsFact: DSFactLabeledContentStyle { DSFactLabeledContentStyle() }
}
