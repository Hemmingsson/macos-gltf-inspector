import SwiftUI

/// App-default job only (DESIGN.md). Never writes per-window session — new windows read these
/// via `MockSettings.default(for:)` when they seed.
struct ShellDefaultsView: View {
    @State private var autoRotate = SettingKey<Bool>.autoRotate.fallback
    @State private var showFloor = SettingKey<Bool>.showFloor.fallback
    @State private var center = SettingKey<Bool>.center.fallback
    @State private var backdrop = SettingKey<BackdropStyle>.backdrop.fallback
    @State private var didLoad = false

    var body: some View {
        Form {
            Section("New Window Defaults") {
                Picker("Backdrop", selection: $backdrop) {
                    ForEach(BackdropStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Show Floor", isOn: $showFloor)
                Toggle("Auto-Rotate", isOn: $autoRotate)
                Toggle("Center", isOn: $center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .onAppear(perform: loadDefaults)
        .onChange(of: autoRotate) { _, value in write(.autoRotate, value) }
        .onChange(of: showFloor) { _, value in write(.showFloor, value) }
        .onChange(of: center) { _, value in write(.center, value) }
        .onChange(of: backdrop) { _, value in write(.backdrop, value) }
    }

    private func loadDefaults() {
        guard !didLoad else { return }
        didLoad = true
        let store = MockSettings()
        autoRotate = store.default(for: .autoRotate)
        showFloor = store.default(for: .showFloor)
        center = store.default(for: .center)
        backdrop = store.default(for: .backdrop)
    }

    private func write<Value>(_ key: SettingKey<Value>, _ value: Value) {
        guard didLoad else { return }
        MockSettings().setDefault(value, for: key)
    }
}
