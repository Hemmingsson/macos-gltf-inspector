> Read this when: implementing sheets, NavigationSplitView, Inspector, or presentation modifiers.

# Sheet, Navigation & Inspector

**Contents**
- [Sheets](#sheets)
- [NavigationStack](#navigationstack)
- [NavigationSplitView](#navigationsplitview)
- [Inspector](#inspector)
- [Presentation](#presentation)

## Sheets

Prefer `.sheet(item:)` over `.sheet(isPresented:)` for model content. Sheets own dismiss via `@Environment(\.dismiss)` — no `onSave`/`onCancel` prop-drilling.

```swift
@State private var selectedItem: Item?

List(items) { item in
    Button(item.name) { selectedItem = item }
}
.sheet(item: $selectedItem) { item in
    ItemDetailSheet(item: item)  // dismisses itself
}
```

Multiple sheet kinds → one `Identifiable` enum + one `.sheet(item:)`:

```swift
enum Sheet: Identifiable {
    case add, edit(Article), categories
    var id: String {
        switch self {
        case .add: "add"
        case .edit(let a): "edit-\(a.id)"
        case .categories: "categories"
        }
    }
}
@State private var presentedSheet: Sheet?
// .sheet(item: $presentedSheet) { switch … }
```

## NavigationStack

Type-safe values + `navigationDestination(for:)`:

```swift
NavigationStack {
    List {
        NavigationLink("Profile", value: Route.profile)
    }
    .navigationDestination(for: Route.self) { route in
        switch route {
        case .profile: ProfileView()
        case .settings: SettingsView()
        }
    }
}
```

Programmatic: `NavigationStack(path: $path)` + `path.append(...)`.

## NavigationSplitView

Sidebar-driven multi-column (iOS 16+ / macOS 13+). Two-column:

```swift
NavigationSplitView {
    List(items, selection: $selectedItem) { item in Text(item.name) }
} detail: {
    if let selectedItem, let item = items.first(where: { $0.id == selectedItem }) {
        ItemDetailView(item: item)
    } else {
        ContentUnavailableView("Select an Item", systemImage: "doc")
    }
}
```

Three-column: sidebar / content / detail with separate selection state.

Config: `columnVisibility:`, `.navigationSplitViewColumnWidth(min:ideal:max:)`, `preferredCompactColumn:`, `.navigationSplitViewStyle(.balanced | .prominentDetail)`.

| Platform | Behavior |
|----------|----------|
| macOS | Always side-by-side; translucent sidebar; drag-resize |
| iPad regular | Overlay or push; toolbar visibility toggle |
| Compact / iPhone | Collapses to `NavigationStack` |

## Inspector

iOS 17+ / macOS 14+. Trailing column on wide; adapts to sheet on compact.

```swift
MyEditorView()
    .inspector(isPresented: $showInspector) {
        InspectorContent()
            .inspectorColumnWidth(min: 200, ideal: 250, max: 400)
    }
```

Fixed width: `.inspectorColumnWidth(300)`. Add `InspectorCommands` for the default toggle shortcut.

## Presentation

```swift
.fullScreenCover(isPresented: $show) { FullScreenView() }

.popover(isPresented: $show) {
    PopoverContentView()
        .presentationCompactAdaptation(.popover)  // stay popover on iPhone
}
```

Alerts / confirmation dialogs: `latest-apis.md`.
