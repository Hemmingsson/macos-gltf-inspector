import SwiftUI

/// Inline `Picker` for a `Menu` / `DSGlassMenuButton` label. AppKit draws the checkmark column;
/// PreviewUI feature code must not call `Picker(` itself.
public struct DSInlineMenuPicker<SelectionValue: Hashable, Content: View>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let content: Content

    public init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    public var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
