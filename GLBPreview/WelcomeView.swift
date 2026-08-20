import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("GLB Preview")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .onAppear { configureWelcomeWindow() }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private func configureWelcomeWindow() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
            return
        }
        window.identifier = NSUserInterfaceItemIdentifier(WelcomeWindow.id)
        HostWindowChrome.apply(to: window)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        GLBDocumentOpening.handleDrop(providers) { url in
            try await openDocument(at: url)
        }
    }
}
