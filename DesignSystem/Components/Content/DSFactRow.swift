import SwiftUI

/// A read-only "label · value" fact: Triangles 12, File size 2 KB, Used by Cube, Sphere.
///
/// A `LabeledContent` styled with `DSFactLabeledContentStyle`, so it keeps the system's label /
/// value semantics (VoiceOver reads "Triangles, 12" as one element). The value is selectable
/// text, so a count or name can be copied.
public struct DSFactRow<Value: View>: View {
    private let label: String
    private let value: Value

    /// Custom value view (a swatch plus text, say). It still gets the value typography.
    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        LabeledContent {
            value
        } label: {
            Text(label)
        }
        .labeledContentStyle(.dsFact)
    }
}

public extension DSFactRow where Value == Text {
    /// Text value.
    init(_ label: String, value: String) {
        self.init(label) { Text(value) }
    }
}

/// `LabeledContent` as a fact row: label leading in `.secondary` callout, value trailing in
/// `.primary` monospaced-digit callout (`DS.Font.value`), selectable, wrapping trailing-aligned
/// when long.
public struct DSFactLabeledContentStyle: LabeledContentStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            configuration.label
                .font(DS.Font.callout)
                .foregroundStyle(DS.Color.textSecondary)
            Spacer(minLength: DS.Spacing.m)
            configuration.content
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

public extension LabeledContentStyle where Self == DSFactLabeledContentStyle {
    /// The design system's fact-row style. See `DSFactLabeledContentStyle`.
    static var dsFact: DSFactLabeledContentStyle { DSFactLabeledContentStyle() }
}

// MARK: - Previews

#Preview("Fact row") {
    DSContentPreviewStage {
        VStack(spacing: DS.Spacing.s) {
            DSFactRow("Triangles", value: 12.formatted())
            DSFactRow("Meshes · Materials", value: "1 · 1")
            DSFactRow("Textures", value: "1 · max 192²")
            DSFactRow("File size", value: "2 KB")
        }
    }
}

#Preview("Fact row long text, dark") {
    DSContentPreviewStage {
        VStack(spacing: DS.Spacing.s) {
            DSFactRow("Used by", value: "Cube, Sphere, Cylinder, Cone, Torus, Suzanne")
            DSFactRow("A label long enough to squeeze its value", value: "1,234,567")
            DSFactRow("Empty", value: "")
        }
    }
    .preferredColorScheme(.dark)
}
