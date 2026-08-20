import SwiftUI

/// Hover reveals short option labels. Labels jump to that option; the icon cycles.
/// `None` stays in the cycle but is omitted from the strip; the icon looks inactive then.
struct PreviewCycleMenu<Icon: View>: View {
    let options: [String]
    @Binding var index: Int
    var tint: (Bool) -> Color
    @ViewBuilder var icon: (Double) -> Icon

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            if hovering, !visibleOptions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(visibleOptions, id: \.offset) { item in
                        Button {
                            select(item.offset)
                        } label: {
                            Text(item.element)
                                .font(.system(size: 11, weight: item.offset == index ? .semibold : .regular))
                                .foregroundStyle(tint(item.offset == index))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
            Button {
                cycle()
            } label: {
                icon(PreviewDebugMode.variableValue(index: index, count: options.count))
                    .frame(width: 24, height: 24)
                    .opacity(isNoneSelected ? 0.4 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(currentTitle)
        }
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .onChange(of: options.count) { _, _ in
            if !options.indices.contains(index) {
                index = 0
            }
        }
    }

    private var isNoneSelected: Bool {
        options.indices.contains(index) && options[index] == "None"
    }

    private var visibleOptions: [(offset: Int, element: String)] {
        options.enumerated().filter { $0.element != "None" }
    }

    private var currentTitle: String {
        options.indices.contains(index) ? options[index] : ""
    }

    private func cycle() {
        guard !options.isEmpty else { return }
        select((index + 1) % options.count)
    }

    private func select(_ next: Int) {
        guard options.indices.contains(next), next != index else { return }
        index = next
    }
}
