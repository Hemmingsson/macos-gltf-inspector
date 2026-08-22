import AppKit
import SwiftUI

struct HostAboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Link(
                        "github.com/\(GLBUpdateConfig.githubRepo)",
                        destination: GLBUpdateConfig.githubURL
                    )
                } label: {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GLB Preview")
                                .font(.title2)
                            Text(versionLine)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .settingsFormChrome()
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
