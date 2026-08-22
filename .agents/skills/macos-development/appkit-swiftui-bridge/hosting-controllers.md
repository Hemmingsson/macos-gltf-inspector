# Hosting Controllers

> Read this when: embedding SwiftUI in AppKit via `NSHostingView` / `NSHostingController`, or debugging animation, first-click, or scroll in a hybrid window.

## Contents

- [Which host](#which-host)
- [Pitfalls](#pitfalls)
- [Sizing](#sizing)

SwiftUI inside AppKit. Scenes: `swiftui-expert-skill`. AppKit-in-SwiftUI: `nsviewrepresentable.md`.

## Which host

| Type | Use |
|------|-----|
| `NSHostingView` | Embed in an `NSView` tree (cells, chrome, popover) |
| `NSHostingController` | Sheet, split item, tab, window `contentViewController` |

Pin with Auto Layout. Set `sizingOptions` (`.intrinsicContentSize`, `.minSize`).

## Pitfalls

**Animation:** Host frame/`animator()` often jumps. Animate inside SwiftUI. Prefer changing SwiftUI state that owns layout, not only the host frame. Prefer a SwiftUI window for animated chrome.

**First click:** Inactive window’s first mouse-down activates and may miss the control. Opt into first-mouse when product needs click-through:

```swift
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
```

Menu-bar popovers also need `NSApp.activate` (menu-bar product notes (n/a for this app)).

**Scroll:** One scroll owner. Host inside `NSScrollView` → SwiftUI may eat the wheel; forward:

```swift
override func scrollWheel(with event: NSEvent) {
    if enclosingScrollView != nil { nextResponder?.scrollWheel(with: event) }
    else { super.scrollWheel(with: event) }
}
```

If SwiftUI owns scrolling, do not wrap the host in `NSScrollView`.

## Sizing

```swift
let hosting = NSHostingView(rootView: MyView(model: model))
hosting.sizingOptions = [.intrinsicContentSize, .minSize]
```

Pass `@Observable` model / bindings into `rootView`. Mutate the model for updates; new `rootView` only for structural changes. Tear down with the controller.
