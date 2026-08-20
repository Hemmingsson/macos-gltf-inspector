> Read this when: storing preferences or touching a legacy Core Data stack. Do not add SwiftData for prefs — this pack does not document a SwiftData stack.

Contents:

- [UserDefaults / AppStorage](#userdefaults--appstorage)
- [Core Data (legacy)](#core-data-legacy)
- [Checklist](#checklist)

# UserDefaults / AppStorage

Small preferences only: booleans, enums, short strings, numbers. Not documents, caches, or blobs.

```swift
struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
        }
        .formStyle(.grouped)
    }
}
```

Prefer `@AppStorage` in SwiftUI settings. Use a `UserDefaults` App Group suite when sharing with extensions (`../macos-capabilities/`).

# Core Data (legacy)

Keep Core Data when the app already has a large stack or APIs SwiftData still lacks. Do not add Core Data to a new small app.

A small Mac document / Quick Look viewer often needs no object graph — files on disk plus prefs. If you later have real models, go to the SwiftData skill; do not invent a store here.

# Checklist

- [ ] Simple prefs → `@AppStorage` / UserDefaults
- [ ] Secrets → Keychain
- [ ] Extension-shared prefs → App Group suite
- [ ] Models / queries → SwiftData skill
