> Read this when: choosing Mac navigation or multi-window shape. Skip for small single-window viewers that already fit views + `@Observable` + functions.

Contents:

- [NavigationSplitView](#navigationsplitview)
- [Multi-window](#multi-window)
- [Coordinator](#coordinator)

# NavigationSplitView

Default Mac chrome for list-plus-detail (and optional inspector). Keep selection and column state on `@Observable` types or view `@State` — not a navigation object graph.

```swift
@Observable
final class BrowserModel {
    var selectedID: UUID?
}

struct HostWindow: View {
    @State private var browser = BrowserModel()

    var body: some View {
        NavigationSplitView {
            OutlinerView(selection: $browser.selectedID)
        } detail: {
            PreviewPane(id: browser.selectedID)
        }
    }
}
```

Scene / toolbar / glass chrome APIs: `swiftui-expert-skill`. This file only decides the split.

Do not add a coordinator to push the detail column. Bind selection.

# Multi-window

Use scenes, not a custom window manager:

- `WindowGroup` — documents or repeatable previews
- `Window` — one Settings / Utility window
- `openWindow(id:)` / `WindowGroup(id:)` — named extra windows

Each window gets its own `@State`. Share process-wide settings via `@AppStorage` or a small `@Observable` in the environment — not a singleton `AppState` that owns every document.

```swift
@main
struct GLTFInspectorApp: App {
    var body: some Scene {
        WindowGroup {
            HostWindow()
        }
        Window("Settings", id: "settings") {
            SettingsRootView()
        }
    }
}
```

# Coordinator

Only if navigation *is* the product (a flow app whose primary job is routing). Otherwise selection bindings and scenes are enough.
