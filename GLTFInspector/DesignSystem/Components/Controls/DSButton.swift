import SwiftUI

/// A standard push button in one of the design system's three emphases, at small or regular size.
///
/// Thin on purpose: each variant is a system `ButtonStyle` (`.bordered`, `.borderless`,
/// `.borderedProminent`), so focus rings, pressed states, accent and Increase Contrast all come
/// from AppKit. Glass buttons for floating chrome are `DSGlass*`, not this.
struct DSButton<Label: View>: View {
    /// Visual emphasis.
    enum Variant: Sendable {
        /// Default secondary action — "Reset" in a popover. `.bordered`.
        case bordered
        /// Inline, chrome-less action inside a row or card. `.borderless`.
        case borderless
        /// The one primary action of a surface. `.borderedProminent` (accent fill).
        case prominent
    }

    /// Control size. Maps to `ControlSize`; never a fixed height.
    enum Size: Sendable {
        case small
        case regular

        var controlSize: ControlSize {
            switch self {
            case .small: .small
            case .regular: .regular
            }
        }
    }

    private let variant: Variant
    private let size: Size
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    /// Custom label.
    init(
        variant: Variant = .bordered,
        size: Size = .regular,
        role: ButtonRole? = nil,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        let button = Button(role: role, action: action) { label }
            .controlSize(size.controlSize)

        switch variant {
        case .bordered: button.buttonStyle(.bordered)
        case .borderless: button.buttonStyle(.borderless)
        case .prominent: button.buttonStyle(.borderedProminent)
        }
    }
}

extension DSButton where Label == Text {
    /// Text-only button.
    init(
        _ title: String,
        variant: Variant = .bordered,
        size: Size = .regular,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.init(variant: variant, size: size, role: role, action: action) { Text(title) }
    }
}
