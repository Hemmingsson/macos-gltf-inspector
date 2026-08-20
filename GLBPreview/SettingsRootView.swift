import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case preview
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .preview: "Preview"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .preview: "cube.transparent"
        case .about: "info.circle"
        }
    }
}

enum SettingsAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func apply(_ raw: String) {
        let appearance = SettingsAppearance(rawValue: raw) ?? .system
        NSApp.appearance = appearance.nsAppearance
    }
}

struct SettingsRootView: View {
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane {
            case .general:
                GeneralSettingsPane()
            case .preview:
                PreviewSettingsPane()
            case .about:
                AboutSettingsPane()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 660, minHeight: 420)
    }
}

extension View {
    func settingsFormChrome() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}

private struct GeneralSettingsPane: View {
    @AppStorage(SettingsKeys.appearance) private var appearance = SettingsAppearance.system.rawValue
    @State private var isDefaultApplication = false
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(SettingsAppearance.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appearance) { _, newValue in
                    SettingsAppearance.apply(newValue)
                }
            }

            Section {
                Button("Set as Default Application") {
                    setAsDefaultApplication()
                }
                .disabled(isDefaultApplication)
                if let defaultAppName {
                    Text("Current default: \(defaultAppName)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("macOS may still confirm the change. Finder and Quick Look can keep their own handlers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let defaultAppError {
                Section {
                    Text(defaultAppError)
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.general.title)
        .onAppear {
            SettingsAppearance.apply(appearance)
            refreshDefaultApp()
        }
    }

    private var glTFTypes: [UTType] {
        [UTType("org.khronos.glb"), UTType("org.khronos.gltf")].compactMap { $0 }
    }

    private func refreshDefaultApp() {
        let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let handlers = glTFTypes.map { type -> URL? in
            NSWorkspace.shared.urlForApplication(toOpen: type)?.resolvingSymlinksInPath()
        }
        isDefaultApplication = !handlers.isEmpty && handlers.allSatisfy { $0 == appURL }
        defaultAppName = handlers.compactMap { url in
            url.map { FileManager.default.displayName(atPath: $0.path) }
        }.first
    }

    private func setAsDefaultApplication() {
        defaultAppError = nil
        let appURL = Bundle.main.bundleURL
        let types = glTFTypes
        Task {
            do {
                for type in types {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                }
                await MainActor.run { refreshDefaultApp() }
            } catch {
                await MainActor.run {
                    defaultAppError = error.localizedDescription
                }
            }
        }
    }
}

private struct PreviewSettingsPane: View {
    @AppStorage(SettingsKeys.autoRotate) private var autoRotate = true
    @AppStorage(SettingsKeys.background) private var background = PreviewBackground.window.rawValue
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    private let store = AppLookStore.shared
    @State private var importError: String?

    var body: some View {
        Form {
            Section("Motion") {
                Toggle(isOn: $autoRotate) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-rotate")
                        Text("Orbit the model when using the Fit camera. Reduced Motion turns this off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section("Appearance") {
                Picker("Background", selection: $background) {
                    ForEach(PreviewBackground.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Text("Used by the app and as the initial Quick Look backdrop. Both can cycle colors from the preview icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show toolbar on open", isOn: $showToolbar)
                    .toggleStyle(.switch)
            }

            Section {
                Toggle("Use environment map", isOn: useEnvironmentMapBinding)
                    .toggleStyle(.switch)

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
        .navigationTitle(SettingsPane.preview.title)
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

/// Horizontal strip of environment previews; selected tile gets an accent ring.
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

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
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
