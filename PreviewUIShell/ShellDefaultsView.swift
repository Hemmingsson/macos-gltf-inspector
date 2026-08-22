import SwiftUI

/// Shell Settings scene — writes app defaults only (P34).
struct ShellDefaultsView: View {
    var body: some View {
        PreviewSettingsRoot(store: .shared)
    }
}
