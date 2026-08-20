> Read this when: configuring Mac window chrome — toolbar style, window size/placement, `NavigationSplitView` / Inspector, or `Commands`.

# macOS Window and Toolbar Styling

`MenuBarExtra` styles = scene API here. LSUIElement/agent: `macos-development/macos-capabilities/menubar.md`. Glass 26+: `liquid-glass.md`.

**Contents**
- [Lookup](#lookup)
- [Toolbars & window](#toolbars--window)
- [MenuBarExtra / nav / commands](#menubarextra--nav--commands)

## Lookup

| API | Avail | Mac-only | Role |
|-----|-------|:--------:|------|
| `windowToolbarStyle` | 11+ | Yes | `.unified` / `.unifiedCompact` / `.expanded` |
| `windowStyle` | 11+ | No | `.hiddenTitleBar` |
| `windowResizability` | 13+ | No | Resize/zoom policy |
| `defaultSize` / `defaultPosition` | 13+ | No | First-open |
| `windowIdealPlacement` | 15+ | No | Display-geometry placement |
| `menuBarExtraStyle` | 13+ | Yes | `.menu` / `.window` |
| `NavigationSplitView` | 13+ | No | Columns; translucent sidebar |
| `inspector` | 14+ | No | Trailing panel |

## Toolbars & window

Prefer `.unified` / `.unifiedCompact`. `.expanded` only for extra toolbar row. 26+: remove conflicting `.toolbarBackground`. Group with `ToolbarSpacer` (`latest-apis.md`).

```swift
WindowGroup { ContentView().frame(minWidth: 600, minHeight: 400) }
.windowToolbarStyle(.unified)
.windowStyle(.titleBar)  // or .hiddenTitleBar
.defaultSize(width: 900, height: 600)
.defaultPosition(.center)
.windowResizability(.contentMinSize)  // or .contentSize (fixed) / .automatic
```

`.hiddenTitleBar` for media/custom chrome, not everyday docs. Content fills: window background styles, not fake glass.

macOS 15+: `.windowIdealPlacement { context in WindowPlacement(…) }` from `context.defaultDisplay.visibleArea`.

## MenuBarExtra / nav / commands

`.menu` = dropdown; `.window` = panel. Lifecycle/Quit: `macos-scenes.md`.

Mac `NavigationSplitView` always side-by-side; `.navigationSplitViewColumnWidth`; don't substitute `HSplitView` for sidebar nav. Inspector: `.inspectorColumnWidth(min:ideal:max:)`.

```swift
.commands {
    CommandMenu("Tools") {
        Button("Run") { }.keyboardShortcut("r", modifiers: [.command, .shift])
    }
    CommandGroup(after: .newItem) { Button("New From Template...") { } }
}
```

`CommandGroup`: `.replacing` / `.before` / `.after`. Gate Mac-only modifiers with `#if os(macOS)`.
