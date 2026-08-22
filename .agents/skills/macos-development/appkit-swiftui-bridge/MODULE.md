# AppKit–SwiftUI Bridge

Hybrid wrapping, hosting, and bridge state. Prefer `@Observable` for new shared models. Defer pure SwiftUI to `swiftui-expert-skill`.

## Large lists (measure first)

1. Prefer SwiftUI `List` / `Table`.
2. Profile with Instruments on a real Mac.
3. Only then wrap `NSTableView` in `NSViewRepresentable` (`nsviewrepresentable.md`).

Do not default to AppKit at an arbitrary row count.

## When to bridge

- `NSViewRepresentable`: no SwiftUI equivalent (rich `NSTextView`, Metal host) or a **measured** list need.
- `NSHostingView` / `NSHostingController`: SwiftUI inside an AppKit app or split/sheet.
- Pure SwiftUI: new work with adequate SwiftUI coverage.

## Modules

| Need | File |
|------|------|
| `NSViewRepresentable` + measured `NSTableView` | `nsviewrepresentable.md` |
| Hosting pitfalls (animation, first click, scroll) | `hosting-controllers.md` |
| Coordinator / `makeCoordinator` state | `state-management.md` |

## Guardrails

- Empty `dismantleNSView` leaks observers. Create the coordinator only in `makeCoordinator`.
- Do not set frames in `makeNSView`; use `sizeThatFits` / intrinsic size.
