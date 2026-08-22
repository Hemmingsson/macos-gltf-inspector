import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
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
        NSApp.appearance = (AppAppearance(rawValue: raw) ?? .system).nsAppearance
    }
}

/// Three-tab Settings. Writes `AppDefaultsStore` only — never a window session.
struct PreviewSettingsRoot: View {
    var store: AppDefaultsStore

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane(store: store)
            }
            Tab("Preview", systemImage: "cube.transparent") {
                PreviewDefaultsPane(store: store)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsPane()
            }
        }
        .scenePadding()
        .frame(maxWidth: 520, minHeight: 240)
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
    var store: AppDefaultsStore
    @State private var isDefaultApplication = false
    @State private var defaultAppName: String?
    @State private var defaultAppError: String?

    private var showsDefaultApp: Bool {
        Bundle.main.bundleIdentifier == "com.laurie.GLBPreview"
    }

    var body: some View {
        Form {
            Section("Appearance") {
                LabeledContent("Appearance") {
                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            if showsDefaultApp {
                Section {
                    LabeledContent("Default app") {
                        Button("Set as Default Application") {
                            setAsDefaultApplication()
                        }
                        .disabled(isDefaultApplication)
                    }
                    if let defaultAppName {
                        LabeledContent("Current default") {
                            Text(defaultAppName)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("macOS may still confirm the change. Finder and Quick Look can keep their own handlers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let defaultAppError {
                Section {
                    Text(defaultAppError)
                        .foregroundStyle(.red)
                }
            }
        }
        .settingsFormChrome()
        .onAppear {
            AppAppearance.apply(store.value(for: .appearance))
            refreshDefaultApp()
        }
    }

    private var appearanceBinding: Binding<String> {
        Binding(
            get: { store.value(for: .appearance) },
            set: { raw in
                store.set(raw, for: .appearance)
                AppAppearance.apply(raw)
            }
        )
    }

    private var glTFTypes: [UTType] {
        [UTType(filenameExtension: "glb"), UTType(filenameExtension: "gltf")].compactMap { $0 }
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
        Task {
            do {
                for type in glTFTypes {
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

private struct PreviewDefaultsPane: View {
    var store: AppDefaultsStore

    private let catalog: [(raw: String, title: String)] = [
        ("neutral", "Studio Neutral"),
        ("field", "Field"),
        ("Colorful_Studio", "Colorful Studio"),
    ]

    var body: some View {
        Form {
            Section("Motion") {
                Toggle("Auto-rotate", isOn: boolBinding(for: .autoRotate))
                Toggle("Polar floor", isOn: boolBinding(for: .showFloor))
            }

            Section("Appearance") {
                Picker("Background", selection: backdropBinding) {
                    ForEach(BackdropStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Show pills on open", isOn: boolBinding(for: .showPills))
            }

            Section {
                Toggle("Use environment map", isOn: boolBinding(for: .useEnvironmentMap))
                Picker("Environment", selection: catalogBinding) {
                    ForEach(catalog, id: \.raw) { item in
                        Text(item.title).tag(item.raw)
                    }
                }
                Button("Add your own…") {
                    addCustomHDR()
                }
                if !store.value(for: .customEnvironmentFile).isEmpty {
                    Text(store.value(for: .customEnvironmentFile))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Custom HDR and EXR files are remembered as a path for the host adapter. Decode stays in Shared/PreviewLighting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .settingsFormChrome()
    }

    private func boolBinding(for key: SettingKey<Bool>) -> Binding<Bool> {
        Binding(
            get: { store.value(for: key) },
            set: { store.set($0, for: key) }
        )
    }

    private var backdropBinding: Binding<BackdropStyle> {
        Binding(
            get: { store.value(for: .backdrop) },
            set: { store.set($0, for: .backdrop) }
        )
    }

    private var catalogBinding: Binding<String> {
        Binding(
            get: { store.value(for: .environmentCatalog) },
            set: { raw in
                store.set(raw, for: .environmentCatalog)
                store.set("", for: .customEnvironmentFile)
            }
        )
    }

    private func addCustomHDR() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "hdr"),
            UTType(filenameExtension: "exr"),
        ].compactMap { $0 }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.set(url.lastPathComponent, for: .customEnvironmentFile)
        store.set(true, for: .useEnvironmentMap)
    }
}

private struct AboutSettingsPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Link(
                        "github.com/Hemmingsson/macos-gltf-preview",
                        destination: URL(string: "https://github.com/Hemmingsson/macos-gltf-preview")!
                    )
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "GLB Preview"
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}
