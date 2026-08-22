# macOS Views

> Read this when: building Mac-specific SwiftUI views — split panes, `Table` styling, pasteboard, file dialogs, or cross-app drag and drop.

AppKit wrapping (`NSViewRepresentable`, coordinators, hosting) is `macos-development/appkit-swiftui-bridge`. Do not re-teach it here.

## Contents

- [Lookup](#lookup)
- [HSplitView and VSplitView](#hsplitview-and-vsplitview)
- [Table styling](#table-styling)
- [Copy, paste, pasteboard](#copy-paste-pasteboard)
- [File operations](#file-operations)
- [Drag and drop](#drag-and-drop)
- [AppKit](#appkit)

## Lookup

| API | Availability | Mac-only | Role |
|-----|-------------|:--------:|------|
| `HSplitView` / `VSplitView` | macOS 10.15+ | Yes | Equal-peer resizable panes |
| `Table` | macOS 12+ | No | Multi-column; compact iOS hides extra columns |
| `PasteButton` | macOS 10.15+ | No | System paste control; does **not** auto-validate on Mac |
| `copyable(_:)` | macOS 10.15+ | No | Participate in Copy (Transferable) |
| `fileImporter` / `fileExporter` / `fileMover` | macOS 11+ | No | Native open/save/move panels |
| `fileDialogMessage(_:)` and siblings | macOS 13+ | Yes | Panel copy |
| `draggable` / `dropDestination` | macOS 11+ | No | Cross-app drag, including Finder |

There is no `CopyButton`.

## HSplitView and VSplitView

Equal-peer IDE-style panes with user-draggable dividers. `NavigationSplitView` is for sidebar-driven navigation, not this.

```swift
HSplitView {
    FileTreeView()
        .frame(minWidth: 200)
    CodeEditorView()
        .frame(minWidth: 400)
    PreviewPane()
        .frame(minWidth: 200)
}
```

`VSplitView` is the same on the vertical axis (`minHeight`).

## Table styling

Creation, selection, sorting, identity, and compact-column pitfalls: `list-patterns.md`.

```swift
Table(people) { /* columns */ }
    .tableStyle(.bordered)                                    // Mac-only grid
    .tableStyle(.bordered(alternatesRowBackgrounds: true))
    .tableStyle(.inset)
    .tableColumnHeaders(.hidden)
```

No glass on table content.

## Copy, paste, pasteboard

`copyable(_:)` makes a view respond to the system Copy command with `Transferable` payload. Pair with `cuttable` / `pasteDestination` when you also own cut and paste into the view.

```swift
Text(shareableText)
    .copyable(shareableText)
```

`PasteButton` is the system paste *control*. On Mac it does not auto-enable/disable as pasteboard contents change (iOS does).

```swift
PasteButton(payloadType: String.self) { strings in
    pastedText = strings.first ?? ""
}
```

Use `NSPasteboard` only when you need programmatic or non-`Transferable` access.

## File operations

Returned URLs are security-scoped. Always `startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()`.

```swift
.fileImporter(
    isPresented: $showImporter,
    allowedContentTypes: [.pdf],
    allowsMultipleSelection: false
) { result in
    if case .success(let urls) = result, let url = urls.first {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        // use url
    }
}
.fileDialogMessage("Choose a PDF")
.fileDialogConfirmationLabel("Use This File")
```

```swift
.fileExporter(
    isPresented: $showExporter,
    document: document,
    contentType: .plainText,
    defaultFilename: "MyFile.txt"
) { result in
    // Result<URL, Error>
}
.fileExporterFilenameLabel("Export As:")
```

`fileMover()` presents the native move panel.

## Drag and drop

On Mac, drags work across apps (Finder, Mail, others). Prefer `Transferable`:

```swift
Text(item.title)
    .draggable(item)

.dropDestination(for: MyItem.self) { items, _ in
    droppedItems.append(contentsOf: items)
    return true
}
```

`onDrag` / `onDrop` + `NSItemProvider` is legacy. Multi-item `dragContainer` is macOS 26+ (not a general iOS 26 API) — see `latest-apis.md`.

## AppKit

Need an `NSView` / `NSViewController` inside SwiftUI, or `NSHostingView` / `NSHostingController` the other way: `macos-development/appkit-swiftui-bridge`.
