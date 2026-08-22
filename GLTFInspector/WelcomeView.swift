import AppKit
import SwiftUI

struct WelcomeView: View {
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)

            Text("Drop a .glb or .gltf file here to view it")
                .font(.title3)
                .multilineTextAlignment(.center)

            Text("Quick Look previews and Finder thumbnails are already installed. You can close this app if you only need those.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Text("File → Open… also works.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .navigationTitle(appName)
        .onDrop(of: [.fileURL], isTargeted: nil) {
            DocumentOpening.handleDrop($0, openDocument: openDocument)
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "glTF Inspector"
    }
}
