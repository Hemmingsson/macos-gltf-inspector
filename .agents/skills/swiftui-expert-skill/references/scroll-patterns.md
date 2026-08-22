> Read this when: implementing ScrollView, programmatic scroll, scroll geometry, or scroll transitions.

# ScrollView Patterns

**Contents**
- [API choice](#api-choice)
- [ScrollViewReader](#scrollviewreader)
- [Geometry & position](#geometry--position)
- [Transitions & targets](#transitions--targets)

## API choice

| Need | API |
|------|-----|
| iOS 18+ geometry observe | `onScrollGeometryChange(for:of:action:)` |
| iOS 18+ scroll by id/offset/edge | `scrollPosition(_:)` + `ScrollPosition` |
| iOS 17+ optional ID binding | `scrollPosition(id:)` |
| Proxy / older OS | `ScrollViewReader` |

Always `.scrollTargetLayout()` on the layout that holds identified targets.

## ScrollViewReader

Stable IDs; animate when wanted:

```swift
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack {
            ForEach(messages) { MessageRow(message: $0).id($0.id) }
            Color.clear.frame(height: 1).id("bottom")
        }
    }
    .onChange(of: messages.count) { _, _ in
        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}
```

Scroll-to-top: clear sentinel `.id("top")` at the start; toggle a Bool and `scrollTo` / reset.

## Geometry & position

`onScrollGeometryChange` transforms `ScrollGeometry` → `Equatable`; action runs only when that changes. Prefer a `Bool` threshold over raw offset (offset fires every frame):

```swift
.onScrollGeometryChange(for: Bool.self) { geo in
    geo.contentOffset.y + geo.contentInsets.top > 50
} action: { _, past in
    withAnimation { showHeader = !past }
}
```

iOS 18+ programmatic:

```swift
@State private var position = ScrollPosition(idType: Item.ID.self)

ScrollView {
    LazyVStack { ForEach(items) { ItemRow(item: $0) } }
        .scrollTargetLayout()
}
.scrollPosition($position)
// position.scrollTo(id: firstID)
```

iOS 17: `.scrollPosition(id: $scrolledID)`. Pre-18: `GeometryReader` + named coordinate space + `PreferenceKey` (last resort).

## Transitions & targets

iOS 17+. Visual effects via `.visualEffect` (opacity/parallax from `.scrollView` frame) — not layout thrash.

Paging:

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 0) {
        ForEach(pages) { PageView(page: $0).containerRelativeFrame(.horizontal) }
    }
    .scrollTargetLayout()
}
.scrollTargetBehavior(.paging)
```

Snap-to-item: `.scrollTargetBehavior(.viewAligned)` + `.contentMargins`.
