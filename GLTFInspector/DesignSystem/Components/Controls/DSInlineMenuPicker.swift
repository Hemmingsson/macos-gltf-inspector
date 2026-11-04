import SwiftUI

/// Inline `Picker` for a `Menu` / `DSGlassMenuButton` label. AppKit draws the checkmark column;
/// Feature code uses this rather than calling `Picker(` itself.
struct DSInlineMenuPicker<SelectionValue: Hashable, Content: View>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let content: Content

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: $selection) {
            content
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}
