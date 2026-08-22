# NSViewRepresentable

> Read this when: wrapping an AppKit view for SwiftUI, or bridging a **measured** `NSTableView` after Instruments shows List/Table is not enough.

## Contents

- [Protocol](#protocol)
- [Coordinator pitfalls](#coordinator-pitfalls)
- [Measured NSTableView](#measured-nstableview)
- [Layout and animation](#layout-and-animation)

Sole how-to in this tree for `NSViewRepresentable` + measured `NSTableView`. Bridge-state rules: `state-management.md`. Prefer SwiftUI `List`/`Table` first.

## Protocol

```swift
struct MyAppKitView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        // remove observers / cancel timers
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MyAppKitView
        init(_ parent: MyAppKitView) { self.parent = parent }
        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.text = f.stringValue
        }
    }
}
```

`makeNSView`: create/configure only. Data lives in `updateNSView` with change guards. Clean up in `dismantleNSView`.

## Coordinator pitfalls

Coordinator survives view re-creation — use for delegates, target-action, KVO. Refresh `parent` every `updateNSView`. Never allocate a new coordinator in `updateNSView`. Do not store source-of-truth state in the coordinator — write through `Binding` / closures. Details: `state-management.md`.

## Measured NSTableView

Bridge **only** after Instruments shows SwiftUI `List`/`Table` insufficient:

```swift
struct HighPerformanceList: NSViewRepresentable {
    let items: [ListItem]
    var onSelect: (ListItem) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let table = NSTableView()
        let col = NSTableColumn(identifier: .init("main"))
        table.addTableColumn(col)
        table.headerView = nil
        table.style = .plain
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        (scroll.documentView as? NSTableView)?.reloadData()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HighPerformanceList
        init(_ parent: HighPerformanceList) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = tableView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTextField
                ?? NSTextField(labelWithString: "")
            cell.identifier = tableColumn!.identifier
            cell.stringValue = parent.items[row].title
            return cell
        }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let t = notification.object as? NSTableView, t.selectedRow >= 0 else { return }
            parent.onSelect(parent.items[t.selectedRow])
        }
    }
}
```

## Layout and animation

`sizeThatFits` / `intrinsicContentSize` — no manual frames. If `context.transaction.animation != nil`, drive AppKit via `NSAnimationContext` + `animator()`; else set values immediately.
