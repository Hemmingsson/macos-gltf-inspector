import SwiftUI

/// Top of the inspector: the selection's identity. The Open-in button floats over the inspector
/// on the traffic-light line (`RightInspector`), not in this header.
struct NodeHeader: View {
    var name: String
    var kind: NodeKind

    var body: some View {
        IdentityRow(name: name, kind: kind)
            .accessibilityElement(children: .contain)
    }
}
