> Read this when: writing or fixing SwiftUI `#Preview` / PreviewProvider, `@Previewable`, or mock preview data.

# Previews

**Contents**
- [#Preview](#preview)
- [Mock data](#mock-data)
- [@Previewable](#previewable)
- [Diagnostics](#diagnostics)

## #Preview

Prefer `#Preview` (Xcode 15+) over `PreviewProvider`. One `#Preview` per meaningful state.

```swift
#Preview("Dark Mode") {
    ContentView().preferredColorScheme(.dark)
}

#Preview(traits: .sizeThatFitsLayout) { BadgeView(count: 5) }
#Preview(traits: .fixedLayout(width: 300, height: 100)) { CompactBanner(message: "Hi") }
#Preview(traits: .landscapeLeft) { DashboardView() }
```

Wrap destinations in `NavigationStack` so toolbar/title render.

## Mock data

No live network/disk. Static samples on the model; inject via `.environment`:

```swift
extension Item {
    static let sample = Item(id: UUID(), name: "Widget", price: 9.99)
    static let samples: [Item] = [/* … */]
}

@Observable @MainActor
final class CartModel {
    var items: [Item] = []
    var isLoading = false
    static var preview: CartModel {
        let m = CartModel(); m.items = Item.samples; return m
    }
}

#Preview {
    CartView()
        .environment(CartModel.preview)
        .environment(\.locale, Locale(identifier: "ja_JP"))
}
```

Async deps: protocol + sync mock returning sample/`Result` immediately. Named previews for empty/error/loading.

## @Previewable

iOS 18+ — `@State` / `@FocusState` inline in `#Preview`. Below 18: wrapper view.

```swift
#Preview {
    @Previewable @State var isOn = false
    Toggle("Notifications", isOn: $isOn)
}

#Preview {
    @Previewable @FocusState var isFocused: Bool
    TextField("Search", text: .constant(""))
        .focused($isFocused)
        .defaultFocus($isFocused, true)  // not onAppear write
}
```

## Diagnostics

| Symptom | Fix |
|---------|-----|
| Body type mismatch | Final expression must be a `View` |
| `@Previewable` unavailable | Wrapper view or raise deployment |
| Missing environment crash | `.environment(Type.preview)` |
| Hang / blank | Sync mock — async never resolves |
| MainActor isolation | Mark helper / preview `@MainActor` |
