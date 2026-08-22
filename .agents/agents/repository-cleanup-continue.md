---
name: repository-cleanup-continue
description: >-
  Continue hunting cleanup in glTF Inspector. Short loop: inspect, create a dex
  task only when evidence justifies it, implement, verify, repeat. Use when
  asked to keep looking for cleanup, leftover complexity, or another pass
  after reduction/simplification.
model: inherit
---

# Continue cleanup — glTF Inspector

Keep going. The previous pass is not the finish line.

Find remaining unnecessary complexity in this repo. Do not start from a refactor list. Do not ask the user what to delete. Discover it from the code, runtime, and measurements.

## Product

Native macOS host + Quick Look + Finder thumbnails for `.glb` / `.gltf`. RealityKit. Preserve open → convert → render, extensions, and failed loads that show copy not a spinner.

## Dex

Primary worktree only. Create tasks **on the fly** when a finding has evidence.

```bash
dex list >/dev/null 2>&1 || dex init
dex list --ready
```

If a campaign epic already exists, add children. If not, create one with goal + constraints only — no cleanup agenda.

`dex start` before edits. `dex complete` with proof. Never put dex IDs in commits.

## Loop

1. Inspect as if you inherited the repo today.
2. Ask: does this need to exist? Is this the simplest place for it? One consumer? Dead? Duplicate? Speculative? Fighting the platform?
3. If justified, create a dex task (why, evidence, done-when, verification).
4. Implement the smallest defensible change.
5. Prove it (`xcodegen` + tests; `./scripts/proof.sh` / real window when convert, render, or UI state changed).
6. Reinspect. Repeat.

Stop only when another full look finds no high-confidence cleanup with real net benefit.

## Do not

Preserve something because it survived the last pass. Add architecture. Invent folder-browser flows. Mutate `@Observable`/`@State` in `View.init` or RealityView `make`/`update`. Block first paint on IBL. Invent Apple APIs. Push unless asked.

When done: what you removed or simplified, how you verified, what remains and why.
