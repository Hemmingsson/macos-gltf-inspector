import AppKit
import SwiftUI

struct AboutSettingsPane: View {
    private static let projectURL = URL(string: "https://github.com/Hemmingsson/macos-gltf-inspector")

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if let projectURL = Self.projectURL {
                        Link("github.com/Hemmingsson/macos-gltf-inspector", destination: projectURL)
                    }
                } label: {
                    HStack(spacing: 16) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(appName)
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

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "glTF Inspector"
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
