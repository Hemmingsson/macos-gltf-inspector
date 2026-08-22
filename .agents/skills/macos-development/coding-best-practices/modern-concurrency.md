# Modern concurrency (Swift 6)

> Read this when: reviewing Swift 6 isolation, Sendable, `@MainActor`, or actor pitfalls. Skip if the task is ordinary async/await.

## Contents

- [Swift 6 isolation](#swift-6-isolation)
- [MainActor](#mainactor)
- [Sendable and actors](#sendable-and-actors)
- [Checklist](#checklist)

## Swift 6 isolation

Enable complete checking. Isolation is part of the type: a `@MainActor` class is not a general service.

```swift
@Observable
@MainActor
final class PreviewSession { var url: URL? }

struct Loader: Sendable {
    func data(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}
```

I/O and convert off the main actor; hop back only to mutate UI. Do not mark `nonisolated` then read isolated state.

## MainActor

UI, `@Observable` UI state, AppKit UI callbacks → `@MainActor`. File I/O / networking / convert → not. Prefer `await` onto a `@MainActor` method over `MainActor.run` / `DispatchQueue.main`.

`Task { }` from `@MainActor` inherits isolation. `Task.detached` drops it — pass `Sendable` values only.

## Sendable and actors

Sendable fields in structs/enums: fine. Classes: `final` + immutable, actor, or do not cross isolation. Leaving-isolation closures: `@Sendable`. `@unchecked Sendable` only with an explicit lock story.

Actor hop is an await — reentrancy can mutate state before resume. Do not use an actor as a ViewModel; UI stays `@MainActor` + `@Observable`. Pass values (not the actor) into UI code. Check cancellation on long loops.

## Checklist

- [ ] Complete concurrency checking on
- [ ] UI isolated; services not
- [ ] Boundary types Sendable
- [ ] No naked `@unchecked Sendable`
- [ ] `Task.checkCancellation` on long work
- [ ] No leftover `DispatchQueue.main.async` for UI hops
