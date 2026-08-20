> Read this when: writing or reviewing `ForEach`, `List`, or `Table` — identity, unary rows, filtering, or Table sorting/compact pitfalls.

# List and Table Patterns

Prefer SwiftUI `List` / `Table`. Profile first; if insufficient → `macos-development/appkit-swiftui-bridge`. No glass on list/table content (`liquid-glass.md`).

**Contents**
- [Identity](#identity)
- [Unary rows & filtering](#unary-rows--filtering)
- [List chrome](#list-chrome)
- [Table](#table)

## Identity

Never `.indices` or `\.offset` for dynamic content. Id must **outlive** the view and not change on edit (`var id: String { title }` drops focus mid-edit). No minting ids in `body`. Cheap to hash; unique (URL-as-id collides). Class `Identifiable` without explicit id → `ObjectIdentifier` (recyclable).

`id: \.self` only for small stable `Hashable`; prefer explicit key. Enumerated: `ForEach(items.enumerated(), id: \.element.id)` (Swift 6.1+ no `Array` wrap).

## Unary rows & filtering

One top-level view per row. Branch **inside** the row type. Top-level `if` without `else` = 0-or-1 — filter the collection. No inline `items.filter` in `ForEach` (rebuilds identity). No `AnyView` rows. Debug: `-LogForEachSlowPath YES`.

```swift
ForEach(items) { ItemRow(item: $0) }  // one root; if/else inside ItemRow
```

## List chrome

```swift
List(items) { item in
    ItemRow(item: item)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
}
.listStyle(.plain)
.scrollContentBackground(.hidden)  // before custom .background
.refreshable { await loadItems() }
```

Empty: overlay `ContentUnavailableView` — don't replace `List` identity.

## Table

iOS 16+ / macOS 12+. Data `Identifiable`. Table **does not sort** — re-sort on `sortOrder` change. Selection: `ID` or `Set<ID>`. Compact size class shows **only first column** — put combined content there. Static: `Table(of:columns:rows:)` + `TableRow`. Dynamic columns (17.4+/14.4+): `TableColumnForEach`. Styles: `.inset`, `.tableColumnHeaders(.hidden)`. Mac bordered: `macos-views.md`.
