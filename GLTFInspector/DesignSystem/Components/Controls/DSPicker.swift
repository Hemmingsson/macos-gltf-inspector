import SwiftUI

/// A system `Picker` over a list of options: the title leading and the control trailing at its
/// natural width ("Tone mapping  [Neutral ▾]"), or the control alone with `labelVisibility:
/// .hidden` (the title stays its accessibility label). Optional selections list `nil` as an option.
struct DSPicker<SelectionValue: Hashable, Style: PickerStyle>: View {
    private let title: String
    @Binding private var selection: SelectionValue
    private let options: [SelectionValue]
    private let style: Style
    private let labelVisibility: Visibility
    private let optionTitle: (SelectionValue) -> String

    init(
        _ title: String,
        selection: Binding<SelectionValue>,
        options: [SelectionValue],
        style: Style,
        labelVisibility: Visibility = .visible,
        optionTitle: @escaping (SelectionValue) -> String
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.style = style
        self.labelVisibility = labelVisibility
        self.optionTitle = optionTitle
    }

    var body: some View {
        let picker = Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(optionTitle(option)).tag(option)
            }
        }
        .pickerStyle(style)
        .labelsHidden()

        if labelVisibility == .hidden {
            picker
        } else {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                Text(title)
                    .font(.body)
                    .accessibilityHidden(true) // the picker announces it
                Spacer(minLength: DS.Spacing.m)
                picker.fixedSize()
            }
        }
    }
}
