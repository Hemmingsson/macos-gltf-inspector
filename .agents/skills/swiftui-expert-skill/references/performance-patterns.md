> Read this when: debugging SwiftUI invalidation storms, Equatable/POD views, allocation in `body`, or `@Observable` fan-out.

# SwiftUI Performance

**Contents**
- [Invalidation](#invalidation)
- [Equatable and POD](#equatable-and-pod)
- [Allocation in body](#allocation-in-body)
- [Observable fan-out](#observable-fan-out)
- [Off-main closures](#off-main-closures)
- [Debug](#debug)

## Invalidation

SwiftUI does **not** skip a write of an equal value unless the type is `Equatable` (`@Observable` setters) or you guard:

```swift
.onReceive(publisher) { value in
    if currentValue != value { currentValue = value }
}
```

Hot paths (scroll, gestures, preferences): update state only when a **threshold crosses**, not every tick. For visual scroll effects prefer `scrollTransition` / `visualEffect(in:)` (renderer-side, no `body`). Coarsen measurements (`isWide = width > 600`) when the value must drive logic.

Pass **only** the fields a child reads. A whole config/model object is a broad dependency even with `@Observable`.

Do not put high-frequency values (offset, drag, per-frame progress, hover) in `@Entry` / `.environment(\.key,)` — any environment write checks every reader in the subtree. Hold a coarsened flag on an `@Observable` instead.

Identity storms (unstable `ForEach` ids, non-unary `List` rows): `list-patterns.md`. Cheap `body`/`init`: `view-structure.md`.

## Equatable and POD

Expensive `body` + small inputs → `Equatable` + `.equatable()`. Update `==` when fields are added. Not a default on every view.

**POD** views (plain value fields, no property wrappers) diff with `memcmp`. Wrap a stateful expensive view in a POD parent so the inner type is skipped when inputs are identical.

```swift
struct ExpensiveView: View {          // POD
    let value: Int
    var body: some View { ExpensiveViewInternal(value: value) }
}
private struct ExpensiveViewInternal: View {
    let value: Int
    @State private var item: Item?
    var body: some View { /* heavy */ }
}
```

## Allocation in body

No `DateFormatter()`, decoders, or large arrays allocated in `body`. Prefer `Text(..., format:)`. Sort/filter in the model or `onChange`, not `List(items.sorted { … })`. Derived counts are computed properties, not `@State`.

iOS 26+: nested scroll views with lazy stacks **defer** child loading until about to appear (WWDC25-256). Still prefer `List` for large data.

`.task` cancels when the view disappears — use it instead of unbounded unstructured tasks.

## Observable fan-out

Reading `model.isFavorite(landmark)` that scans `favorites: [Landmark]` depends on the **entire** array — toggling one row re-runs every row. Persist a per-item `@Observable` (`var isFavorite`) and pass that instance to the row.

Granularity traps (computed props, struct fields, collections): `state-management.md`.

## Off-main closures

`Shape.path(in:)`, `visualEffect`, `Layout` methods, and `onGeometryChange` transforms may run off the main thread. They must be `Sendable`. Capture values; don’t touch `@MainActor` `self`:

```swift
.visualEffect { [pulse] content, geometry in
    content.blur(radius: pulse ? 5 : 0)
}
```

## Debug

`#if DEBUG let _ = Self._logChanges() #endif` (iOS 17+, `com.apple.SwiftUI` / “Changed Body Properties”). `_printChanges()` → stdout. `@self` = view value changed; `@identity` = persistent data recycled. Remove before ship.

Instruments: Instruments (not bundled in this skill tree).
