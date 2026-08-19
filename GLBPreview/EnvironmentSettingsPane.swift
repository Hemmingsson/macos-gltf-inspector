import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EnvironmentSettingsPane: View {
    @State private var look = AppLook.current
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Use environment map", isOn: $look.useEnvironmentMap)
                    .toggleStyle(.switch)
                    .onChange(of: look.useEnvironmentMap) { _, _ in
                        persist()
                    }

                Picker("Environment", selection: $look.catalogRaw) {
                    ForEach(GLBKhronosEnvironments.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: look.catalogRaw) { _, _ in
                    look.customFileName = nil
                    persist()
                }

                Button("Add your own…") {
                    addCustomHDR()
                }

                if let name = look.customFileName {
                    Text("Custom: \(name)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Group {
                    if let importError {
                        Text(importError)
                            .foregroundStyle(.red)
                    } else {
                        Text("Custom HDR and EXR files are copied into Application Support. A file that cannot be decoded is ignored.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.environment.title)
        .onAppear {
            look = AppLook.current
        }
    }

    private func persist() {
        AppLook.saveCurrent(look)
    }

    private func addCustomHDR() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.hdrTypes
        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let imported = try Self.importCustomFile(from: source)
            guard GLBPreviewLighting.canDecodeHDR(at: imported.url) else {
                try? FileManager.default.removeItem(at: imported.url)
                importError = "Could not decode \(source.lastPathComponent). The previous environment is unchanged."
                return
            }
            look.customFileName = imported.fileName
            look.useEnvironmentMap = true
            persist()
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private static var hdrTypes: [UTType] {
        [
            UTType(filenameExtension: "hdr"),
            UTType(filenameExtension: "exr"),
        ].compactMap { $0 }
    }

    private static func importCustomFile(from source: URL) throws -> (url: URL, fileName: String) {
        let support = AppLook.supportDirectory()
        let ibl = AppLook.iblDirectory(in: support)
        try FileManager.default.createDirectory(at: ibl, withIntermediateDirectories: true)

        let base = source.lastPathComponent
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        var fileName = base
        var dest = ibl.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: dest.path) {
            fileName = "\(stem)-\(UUID().uuidString.prefix(8)).\(ext)"
            dest = ibl.appendingPathComponent(fileName)
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return (dest, fileName)
    }
}
