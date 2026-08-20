> Read this when: declaring SwiftUI scenes on Mac — `Settings`, `MenuBarExtra`, `WindowGroup`, `Window`, `UtilityWindow`, `DocumentGroup`, or `openWindow`.

# macOS Scenes

Menu-bar **product** architecture (LSUIElement, activation, sandbox): `macos-development/macos-capabilities/menubar.md`. This file = **scene API**.

**Contents**
- [Lookup](#lookup)
- [Settings / MenuBarExtra](#settings--menubarextra)
- [Windows](#windows)
- [Documents & openWindow](#documents--openwindow)

## Lookup

| API | Avail | Mac-only | Role |
|-----|-------|:--------:|------|
| `WindowGroup` | 11+ | No | Multi-instance; tabbing; Window menu |
| `Window` | 13+ | No | Single instance |
| `UtilityWindow` | 15+ | Yes | Floating palette; inherits `FocusedValues` |
| `Settings` | 11+ | Yes | Preferences (Cmd+,) |
| `MenuBarExtra` | 13+ | Yes | `.menu` or `.window` |
| `DocumentGroup` | 11+ | No | File New/Open/Save |

## Settings / MenuBarExtra

```swift
Settings {
    TabView {
        Tab("General", systemImage: "gear") { GeneralSettingsView() }
    }
    .scenePadding().frame(maxWidth: 350, minHeight: 100)
}
```

macOS 14+: `SettingsLink`; `@Environment(\.openSettings)`.

`.menu` = dropdown; `.window` = panel. `isInserted:` + `@AppStorage` to hide — does **not** quit. Terminate via `applicationShouldTerminateAfterLastWindowClosed` and/or explicit Quit. Agent apps: capabilities `menubar.md`.

## Windows

Prefer `WindowGroup` as primary (multi-instance, tabbing). Typed: `WindowGroup("Message", for: Message.ID.self) { $id in … }`.

`Window(id:)` = singleton; `openWindow(id:)` fronts if open. Use for supplementary tools, not primary.

`UtilityWindow` (15+): floats, hides when app inactive, Escape dismisses, View-menu toggle (`.commandsRemoved()` + `WindowVisibilityToggle` to relocate). Reads main-scene `FocusedValues`.

## Documents & openWindow

```swift
DocumentGroup(newDocument: TextFile()) { config in
    ContentView(document: config.$document)
}
@Environment(\.openWindow) private var openWindow
openWindow(id: "connection-doctor")
openWindow(value: message.id)
```

`FileDocument` / `ReferenceFileDocument`. `DocumentGroup(viewing:)` for read-only. Gate Mac-only scenes with `#if os(macOS)`.
