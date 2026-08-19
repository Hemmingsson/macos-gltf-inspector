import SwiftUI

struct HostOutlinerView: View {
    var body: some View {
        Text("Outliner")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(HostColumnChrome())
    }
}
