import SwiftUI

struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GLB Preview")
                            .font(.title2)
                        Text(versionLine)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Link(
                    "github.com/Hemmingsson/macos-gltf-preview",
                    destination: URL(string: "https://github.com/Hemmingsson/macos-gltf-preview")!
                )
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.about.title)
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
