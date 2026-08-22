---
name: metal-realitykit-visionos
description: >
  Use when writing Metal pipelines/shaders/buffers/textures, or RealityKit
  entities/components/systems/RealityView on macOS. Not for SwiftUI UI,
  macOS architecture, concurrency, or visionOS ImmersiveSpace apps.
last_verified: 2026-08-20
review_by: 2027-06-22
---

# Metal & RealityKit (macOS)

GPU and RealityKit for **macOS** windows / Quick Look. Read only the file that matches the task.

Defer: SwiftUI → `swiftui-expert-skill`; macOS architecture / sandbox / extensions → `macos-development`.

## Guardrails

- Never import visionOS immersion APIs into a macOS RealityKit/`RealityView` target (`ImmersiveSpace`, `openImmersiveSpace`, hand/head `AnchorEntity`, `ARKitSession` / `HandTrackingProvider`).
- Never invent Apple types or treat local helpers as SDK APIs.
- RealityView `make`/`update` and `View.init`: **never** write `@State` or `@Observable` inline (see `realitykit-visionos.md` landmines).

## References

- [metal-graphics.md](metal-graphics.md) — device, pipelines, buffers, textures, compute, shaders, pacing
- [realitykit-visionos.md](realitykit-visionos.md) — ECS, RealityView, macOS landmines
