> Read this when: writing or reviewing SwiftUI layout, GeometryReader alternatives, or container ownership.

# Layout Best Practices

**Contents**
- [Relative & context](#relative--context)
- [Container ownership](#container-ownership)
- [Performance](#performance)
- [Full-width & actions](#full-width--actions)

## Relative & context

Prefer relative sizing over magic constants. Never `UIScreen.main.bounds` — views must work as sheets, popovers, embedded content.

```swift
GeometryReader { geo in
    HeaderView().frame(height: geo.size.height * 0.2)
}
// Prefer iOS 17+: containerRelativeFrame(.horizontal) { w, _ in w * 0.8 }
```

## Container ownership

Custom views **own** static containers (`HStack`/`VStack`). Callers own **lazy** / repeatable containers (`LazyVStack`, `List` + `ForEach`).

```swift
// Own static
struct HeaderView: View {
    var body: some View { HStack { Image(systemName: "star"); Text("Title"); Spacer() } }
}

// Caller owns lazy
LazyVStack { ForEach(items) { ItemRow(item: $0) } }
```

## Performance

Flatten deep nesting. One `GeometryReader` max in a path — nested readers thrash. Gate preference updates by threshold (`abs(delta) > 10`), not every pixel.

Business logic lives in `@Observable` services/models, not view closures — see `state-management.md`.

## Full-width & actions

```swift
// Prefer
Text("Hello").frame(maxWidth: .infinity, alignment: .leading)
// Avoid HStack { Text("Hello"); Spacer() }

Button("Publish", action: publishService.handlePublish)  // not multi-line inline logic
```
