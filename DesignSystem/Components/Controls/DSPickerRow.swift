import SwiftUI

/// Shared body of `DSSegmentedPicker` and `DSMenuPicker`: a system `Picker` over a list of
/// options, either with its title as a leading `LabeledContent` label (control pushed trailing) or
/// with the label hidden. Internal — callers use the two public pickers.
struct DSPickerRow<SelectionValue: Hashable, Style: PickerStyle>: View {
    let title: String
    @Binding var selection: SelectionValue
    let options: [SelectionValue]
    let optionTitle: (SelectionValue) -> String
    let labelVisibility: Visibility
    let style: Style

    var body: some View {
        let picker = Picker(selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(optionTitle(option)).tag(option)
            }
        } label: {
            // Kept even when hidden: it is the picker's accessibility label.
            Text(title)
        }
        .pickerStyle(style)
        .labelsHidden()

        if labelVisibility == .hidden {
            picker
        } else {
            LabeledContent {
                picker.fixedSize()
            } label: {
                Text(title)
                    // The picker announces the same title; do not read it twice.
                    .accessibilityHidden(true)
            }
            .labeledContentStyle(DSControlRowLabeledContentStyle())
        }
    }
}

/// Title leading in `.primary` body text, control trailing — the popover control row.
struct DSControlRowLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
            configuration.label
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: DS.Spacing.m)
            configuration.content
        }
    }
}
