import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreviewSettingsPane: View {
    @AppStorage(SettingsKeys.autoRotate) private var autoRotate = true
    @AppStorage(SettingsKeys.showFloor) private var showFloor = true
    @AppStorage(SettingsKeys.background) private var background = PreviewBackground.window.rawValue
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    private let store = AppLookStore.shared
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Motion") {
                LabeledContent {
                    Toggle("Auto-rotate", isOn: $autoRotate)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-rotate")
                        Text("Default for new windows. Open windows keep their own View-menu / toolbar toggle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Toggle("Polar floor", isOn: $showFloor)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Polar floor")
                        Text("Default for new windows. Visual only — does not change orbit. Open windows keep their own toggle.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                LabeledContent("Background") {
                    Picker("Background", selection: $background) {
                        ForEach(PreviewBackground.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Text("Default backdrop for new windows and the initial Quick Look backdrop. Open windows keep their own cycle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Toolbar") {
                    Toggle("Show toolbar on open", isOn: $showToolbar)
                        .labelsHidden()
                }
            }

            Section {
                LabeledContent("Environment map") {
                    Toggle("Use environment map", isOn: useEnvironmentMapBinding)
                        .labelsHidden()
                }

                EnvironmentCatalogPicker(
                    catalogRaw: store.look.catalogRaw,
                    customFileName: store.look.customFileName,
                    onSelectCatalog: { raw in
                        var next = store.look
                        next.catalogRaw = raw
                        next.customFileName = nil
                        store.apply(next)
                    }
                )

                Button("Add your own…") {
                    addCustomHDR()
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
        .onAppear {
            store.reloadFromDisk()
        }
    }

    private var useEnvironmentMapBinding: Binding<Bool> {
        Binding(
            get: { store.look.useEnvironmentMap },
            set: { value in
                var next = store.look
                next.useEnvironmentMap = value
                store.apply(next)
            }
        )
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
            guard PreviewLighting.canDecodeHDR(at: imported.url) else {
                try? FileManager.default.removeItem(at: imported.url)
                importError = "Could not decode \(source.lastPathComponent). The previous environment is unchanged."
                return
            }
            var next = store.look
            next.customFileName = imported.fileName
            next.useEnvironmentMap = true
            store.apply(next)
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

private struct EnvironmentCatalogPicker: View {
    var catalogRaw: String
    var customFileName: String?
    var onSelectCatalog: (String) -> Void

    private var customIsSelected: Bool {
        !(customFileName ?? "").isEmpty
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(KhronosEnvironments.allCases, id: \.rawValue) { option in
                    EnvironmentThumbnailButton(
                        title: option.title,
                        url: PreviewLighting.catalogURL(option),
                        isSelected: !customIsSelected && catalogRaw == option.rawValue
                    ) {
                        onSelectCatalog(option.rawValue)
                    }
                }
                if let name = customFileName, !name.isEmpty {
                    EnvironmentThumbnailButton(
                        title: name,
                        url: AppLook.iblDirectory(in: AppLook.supportDirectory()).appendingPathComponent(name),
                        isSelected: true
                    ) {}
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct EnvironmentThumbnailButton: View {
    let title: String
    let url: URL?
    let isSelected: Bool
    let action: () -> Void

    @State private var image: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 112, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.28),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                }

                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 112)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .task(id: url?.path) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
        guard let url else { return nil }
        return await Task.detached(priority: .utility) {
            guard let cgImage = PreviewLighting.thumbnailImage(from: url) else { return nil }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
