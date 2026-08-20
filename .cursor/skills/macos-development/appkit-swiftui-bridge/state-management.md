# Bridge state (Coordinator)

> Read this when: syncing values across `NSViewRepresentable` / a hosted view — not when learning SwiftUI `@Observable`.

## Contents

- [Owner](#owner)
- [Keep parent fresh](#keep-parent-fresh)
- [What the coordinator may hold](#what-the-coordinator-may-hold)
- [Cleanup and mistakes](#cleanup-and-mistakes)

SwiftUI observation (`@Observable`, `@State`) lives in `swiftui-expert-skill`. Full representable how-to: `nsviewrepresentable.md`.

## Owner

The representable is a value. AppKit callbacks need a long-lived **Coordinator**, created only in `makeCoordinator()`. Never allocate in `updateNSView`. SwiftUI keeps `context.coordinator` for the view’s life.

`NSHostingView` has no Coordinator — pass model/closures into `rootView`.

```swift
func makeCoordinator() -> Coordinator { Coordinator(self) }

final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: MyAppKitView
    init(_ parent: MyAppKitView) { self.parent = parent }
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        parent.text = f.stringValue
    }
}
```

Job: delegates, target-action, KVO / NotificationCenter.

## Keep parent fresh

`makeCoordinator` runs once; the representable is recreated every update. In `updateNSView`:

```swift
context.coordinator.parent = self
if nsView.stringValue != text { nsView.stringValue = text }
```

Write back through `Binding` / closures on `parent`. Do not copy `@State` into the coordinator as source of truth.

## What the coordinator may hold

| OK | Not OK |
|----|--------|
| `parent` (refreshed each update) | Second copy of the model |
| Delegate / target identity | Creating the `NSView` |
| Observations you invalidate | New Coordinator per update |

Shared models are app-owned outside the representable. Coordinator only forwards.

## Cleanup and mistakes

```swift
static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
    coordinator.observation?.invalidate()
}
```

Empty dismantle leaks KVO. Use `[weak self]` in closures that capture AppKit objects.

Avoid: `Coordinator()` in `updateNSView` · uncleared timers · unconditional view writes (cursor/selection reset) · duplicating `@Observable` tutorials here.
