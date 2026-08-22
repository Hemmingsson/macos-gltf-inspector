# RealityKit (macOS)

> Read this when: RealityKit ECS or RealityView on Mac. visionOS immersion APIs are **out of scope** — do not paste them into macOS targets.

Defer SwiftUI observation/`@State` rules to `swiftui-expert-skill`. Prefer `@Observable` over `ObservableObject`.

## Contents

- [Mac landmines](#mac-landmines)
- [Entity hierarchy](#entity-hierarchy)
- [Components & systems](#components--systems)
- [Scene subscriptions](#scene-subscriptions)
- [RealityView](#realityview)

## Mac landmines

Hard rules from shipping a macOS RealityKit host (glTF Inspector). Violating these causes infinite SwiftUI loops, hung spinners, or `EXC_BREAKPOINT`.

1. **Never mutate `@State` / `@Observable` in `View.init` or RealityView `make`/`update`.** Only assign stored props / `_State(initialValue:)` in `init`. Floor/orbit/camera sync belongs in `onAppear` or explicit actions. If `make`/`update` must schedule a write: `Task { @MainActor in … }`.
2. **Do not iterate `RealityViewCameraContent.entities` during update** — crash. Own a `lookRoot` (or similar) entity; put lights under it.
3. **Clear IBL receivers before removing IBL light entities.**
4. **Persist scene entity refs in `@State`** (e.g. a small frame struct), not a plain `let` on the view struct — parent `updateNSView` recreates the struct.
5. Prefer system `.realityViewCameraControls(.orbit)` + `content.cameraTarget` for interactive orbit. One-shot fit/dolly: dedicated helpers — do not hand-roll spherical controls or call `Entity.look(at:from:)` near world +Y without care.
6. Floor toggle is visual only; do not change camera limits when toggling floor.

## Entity hierarchy

```swift
import RealityKit

let root = Entity()
root.name = "SceneRoot"
let child = ModelEntity(
    mesh: .generateSphere(radius: 0.1),
    materials: [SimpleMaterial(color: .blue, isMetallic: true)]
)
child.name = "Sphere"
child.position = [0, 1.5, -2]
root.addChild(child)
_ = root.findEntity(named: "Sphere")
```

## Components & systems

```swift
struct HighlightComponent: Component, Codable, Hashable {
    var color: SIMD3<Float> = [1, 1, 0]
    var intensity: Float = 1.0
}

struct RuntimeStateComponent: TransientComponent {
    var lastUpdateTime: TimeInterval = 0
}

HighlightComponent.registerComponent()
RuntimeStateComponent.registerComponent()

final class HighlightSystem: System {
    private static let query = EntityQuery(where: .has(HighlightComponent.self))

    required init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var h = entity.components[HighlightComponent.self] else { continue }
            h.intensity *= 0.99
            entity.components[HighlightComponent.self] = h
        }
    }
}
HighlightSystem.registerSystem()

entity.components[HighlightComponent.self] = HighlightComponent(intensity: 0.5)
_ = entity.components.has(HighlightComponent.self)
entity.components.remove(HighlightComponent.self)
```

## Scene subscriptions

Hold subscriptions in `@State` if needed, but **attach them outside `make`/`update` state writes** — e.g. capture the subscription into a local and apply via `Task { @MainActor in … }`, or own them on a non-`@Observable` scene object created once.

```swift
_ = scene.subscribe(to: SceneEvents.Update.self) { event in _ = event.deltaTime }
```

## RealityView

Build entities in `make`. Sync props in `update`. **No `@State` / `@Observable` writes in either closure.**

```swift
import SwiftUI
import RealityKit

struct SceneView: View {
    @State private var root = Entity()

    var body: some View {
        RealityView { content in
            if root.children.isEmpty {
                let sphere = ModelEntity(
                    mesh: .generateSphere(radius: 0.1),
                    materials: [SimpleMaterial(color: .blue, isMetallic: true)]
                )
                sphere.position = [0, 1.5, -2]
                root.addChild(sphere)
            }
            if root.parent == nil {
                content.add(root)
            }
        } update: { _ in
            // Read already-captured values; mutate entities only.
            // Need to write @State / @Observable? → Task { @MainActor in … }
        }
    }
}
```

Do **not** `subscriptions.append(...)` (or any other `@State` mutation) inside `make`/`update`.
