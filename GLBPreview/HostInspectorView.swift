import SwiftUI

struct HostInspectorView: View {
    var body: some View {
        Text("Inspector")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HostColumnChrome())
    }
}
