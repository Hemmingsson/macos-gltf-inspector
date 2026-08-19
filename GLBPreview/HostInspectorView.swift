import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HostInspectorView: View {
    var session: ViewerSession?

    var body: some View {
        Group {
            if let session {
                InspectorForm(session: session)
            } else {
                Text("Inspector")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HostColumnChrome())
    }
}

private struct InspectorForm: View {
    @Bindable var session: ViewerSession

    var body: some View {
        Form {
            if let inspectorError = session.inspectorError {
                Text(inspectorError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Section("Background") {
                Toggle("Environment Map", isOn: $session.showEnvironmentMap)
                Toggle("Blur", isOn: $session.blurEnvironment)
                ColorPicker("Background Color", selection: $session.backgroundColor, supportsOpacity: false)
                Picker("Environment Rotation", selection: $session.environmentRotation) {
                    ForEach(ViewerSession.EnvironmentRotation.allCases, id: \.self) { rotation in
                        Text(rotation.rawValue).tag(rotation)
                    }
                }
                Picker("Active Environment", selection: activeEnvironment) {
                    ForEach(GLBKhronosEnvironments.all, id: \.self) { environment in
                        Text(environment.title).tag("catalog:" + environment.rawValue)
                    }
                    ForEach(session.userHDRs, id: \.self) { url in
                        Text(url.lastPathComponent).tag("user:" + url.absoluteString)
                    }
                }
                Button("Add New HDR") {
                    addHDR()
                }
            }

            Section("Lighting") {
                Toggle("Image Based", isOn: $session.imageBased)
                Toggle("Punctual", isOn: $session.punctualLights)
                Slider(value: iblLogIntensity, in: log10(0.01)...log10(10_000)) {
                    Text("IBL Intensity")
                }
                Slider(value: $session.exposure, in: 0...64) {
                    Text("Exposure")
                }
                .disabled(!exposureEnabled)
                Picker("Tone Map", selection: $session.toneMap) {
                    ForEach(ViewerSession.ToneMap.allCases, id: \.self) { toneMap in
                        Text(toneMap.title).tag(toneMap)
                    }
                }
                .disabled(!toneMapEnabled)
            }

            Section("Debug") {}
        }
        .formStyle(.grouped)
        .onChange(of: session.imageBased) { _, _ in session.applyIfBound() }
        .onChange(of: session.punctualLights) { _, _ in session.applyIfBound() }
        .onChange(of: session.iblIntensity) { _, _ in session.applyIfBound() }
        .onChange(of: session.environment) { _, _ in session.applyIfBound() }
        .onChange(of: session.environmentRotation) { _, _ in session.applyIfBound() }
        .onChange(of: session.selectedUserHDR) { _, _ in session.applyIfBound() }
    }

    private var exposureEnabled: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private var toneMapEnabled: Bool {
        if #available(macOS 26, *) { return true }
        return false
    }

    private var iblLogIntensity: Binding<Float> {
        Binding(
            get: { log10(max(session.iblIntensity, 0.01)) },
            set: { session.iblIntensity = pow(10, $0) }
        )
    }

    private var activeEnvironment: Binding<String> {
        Binding(
            get: {
                if let url = session.selectedUserHDR {
                    return "user:" + url.absoluteString
                }
                return "catalog:" + session.environment.rawValue
            },
            set: { newValue in
                if newValue.hasPrefix("user:") {
                    let raw = String(newValue.dropFirst(5))
                    session.selectedUserHDR = session.userHDRs.first { $0.absoluteString == raw }
                } else if newValue.hasPrefix("catalog:"),
                          let environment = GLBKhronosEnvironments(rawValue: String(newValue.dropFirst(8)))
                {
                    session.environment = environment
                    session.selectedUserHDR = nil
                }
            }
        )
    }

    private func addHDR() {
        let panel = NSOpenPanel()
        panel.title = "Add New HDR"
        panel.allowedContentTypes = [UTType(filenameExtension: "hdr") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        guard GLBPreviewLighting.canDecodeHDR(at: url) else {
            session.inspectorError = "Could not load HDR"
            return
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("glb-hdr-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            session.userHDRs.append(dest)
            session.selectedUserHDR = dest
            session.inspectorError = nil
        } catch {
            session.inspectorError = "Could not load HDR"
        }
    }
}
