import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case preview
    case environment
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .preview: "Preview"
        case .environment: "Environment"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .preview: "cube.transparent"
        case .environment: "sun.max"
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
            case .environment:
                EnvironmentSettingsPane()
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
    @AppStorage(SettingsKeys.quitWhenLastWindowCloses) private var quitWhenLastWindowCloses = true
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
                Toggle("Quit when last window closes", isOn: $quitWhenLastWindowCloses)
                    .toggleStyle(.switch)
            }

            Section {
                Button("Set as Default Application") {
                    setAsDefaultApplication()
                }
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
            refreshDefaultAppName()
        }
    }

    private var glTFTypes: [UTType] {
        [UTType("org.khronos.glb"), UTType("org.khronos.gltf")].compactMap { $0 }
    }

    private func refreshDefaultAppName() {
        let names = glTFTypes.compactMap { type -> String? in
            guard let url = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
            return FileManager.default.displayName(atPath: url.path)
        }
        defaultAppName = names.first
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
                await MainActor.run { refreshDefaultAppName() }
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
    @AppStorage(SettingsKeys.playOnOpen) private var playOnOpen = true
    @AppStorage(SettingsKeys.showStats) private var showStats = true
    @AppStorage(SettingsKeys.showToolbar) private var showToolbar = true
    @AppStorage(SettingsKeys.defaultCamera) private var defaultCamera = PreviewDefaultCamera.fit.rawValue

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

                Toggle(isOn: $playOnOpen) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play animations on open")
                        Text("Starts the first clip when the file has animations.")
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

                Picker("Default camera", selection: $defaultCamera) {
                    ForEach(PreviewDefaultCamera.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Quick Look") {
                Toggle("Show file info", isOn: $showStats)
                    .toggleStyle(.switch)
                Toggle("Show toolbar on open", isOn: $showToolbar)
                    .toggleStyle(.switch)
            }
        }
        .settingsFormChrome()
        .navigationTitle(SettingsPane.preview.title)
    }
}

private struct EnvironmentSettingsPane: View {
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
