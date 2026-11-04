# Handover: scene interaction epic (pick, visibility, isolate, gizmos, animation)

Paste everything below the line into a new agent session started in `/Users/mattias/dev/glb-preview`.

---

You are continuing the **scene interaction** epic in the glTF Inspector macOS app (Swift, SwiftUI,
Metal) at `/Users/mattias/dev/glb-preview`. Work autonomously through the backlog until it is done.
Don't hand back after each ticket.

## Read first (in this order)

1. `AGENTS.md`: build and test commands, pitfalls, reference-image rules.
2. `DESIGN.md`: product principles. The non-goals were updated on 2026-11-04: hide/solo, gizmos,
   skeleton and playback are now in scope as **view state, never file edits**.
3. `.agents/plans/2026-11-04-scene-interaction.md`: the spec. It has the coverage table for every
   glTF type, a "Status" section and a "Decisions log".
4. `.agents/research/2026-11-04-khronos-animation-port.md`: required before any Phase 6
   (animation) ticket.
5. The backlog: `dex list 6tjaejue`, `dex list --ready`, `dex show <id> --full`. Every ticket has
   Why / Scope / Done when / Verification and is written for a cold pick-up.

## Current state (2026-11-04)

- **Done, uncommitted on `main`, 132 tests green:**
  - Phase 0: `DESIGN.md`.
  - Phase 1: `Renderer/Scene/MetalDrawFilter.swift`; `ViewOptions.hiddenNodeIndices`,
    `soloNodeIndices` and `isolatedNodeIndex`; `MetalScene.nodeParents` and
    `ancestors(ofNode:)`; `MetalPunctualLight.nodeIndex`.
  - Phase 2: the eye control in `DSOutlineRow` (`DSVisibility`), `OutlinerTree.layerVisibility`,
    `ViewState.hiddenNodes`, `soloNodes`, `toggleHidden`, `toggleSolo` and `showAll`, the context
    menu, the View menu items (⇧⌘H hide, ⌥⇧⌘H solo), and `Node.isHiddenInFile` from
    `KHR_node_visibility`.
- Checkpoints of the working tree: `refs/checkpoints/phase1` and `refs/checkpoints/phase2`, made
  with `git stash create`. Use `git diff refs/checkpoints/phase2` to see what changed since.
- **Next tickets:**
  - `5dwgubib`: on-screen check of Phase 2.
  - Phase 3: `agyhm0sr` pick pass → `qtuda1nk` click selects → `hc4no7yk` layer list reveal, plus
    `yo39dosw` Frame Selection.
  - `2kwjzlmj`: navigation gizmo (live ±X/±Y/±Z balls).
  - Then Phases 4, 5 and 7, which can run in parallel. Phase 6 is a chain from `ifz67ezm` to
    `sygpfhz7`.

## How to work (the user's standing rules)

- **Implement with Haiku, verify with a smarter model.** Dispatch each ticket to a
  `task-implementer` subagent with `model: "haiku"` and `effort: "medium"`. Give it a precise brief:
  the ticket text plus exact file paths and APIs you have read. Let it ship fast. Then **you** review
  the diff, run the tests, fix what it missed yourself, and check UI on screen. Code reading,
  research and review stay on smarter models.
- **One build at a time.** `./scripts/dev.sh` uses one DerivedData folder per branch, so parallel
  builds or tests in the same checkout clash. Run implementers one after another, or give each
  parallel lane its own git worktree (at most about 3 lanes).
- **Verify each ticket:**
  - `./scripts/dev.sh test` must end with `** TEST SUCCEEDED **`; the full suite takes 2–4 min, so
    run it in the background.
  - Pixel references in `TestModels/References/` must stay unchanged. Never regenerate them for a
    default render; a failure means your change altered rendering.
  - UI: `./scripts/dev.sh run <fixture>`, bring the app forward with
    `open -a ".build/glTF Inspector.app"`, then `screencapture -x -R x,y,w,h`. Use the MacOS-MCP
    tools for hover and clicks. Check it yourself and never ask the user to test.
  - Real-window flows: `./scripts/dev.sh uitest` (opt-in; steals focus, which is allowed).
- **UI goes through the design system.** New controls are components in
  `GLTFInspector/DesignSystem/` using `DS` tokens. No hard-coded colours in feature views.
  `DesignSystem` must not import `Renderer` or `GLTFCore`.
- **Tickets:**
  - `dex start <id>` before work.
  - `dex complete <id> --result "<what changed, test count, what was checked on screen, what was
    left>" --no-commit` after verification.
  - Run dex from the repo root in a subshell, `(cd /Users/mattias/dev/glb-preview && dex …)`, so
    your working directory never moves.
  - Add follow-up tickets for gaps you find instead of widening the current ticket.
- **Git:**
  - Do not commit, push, stash-pop, reset or check out unless the user asks.
  - The tree holds uncommitted work from Phases 0–2. Run `git branch --show-current` in the same
    command as any commit.
  - After each verified phase, add a checkpoint:
    `git update-ref refs/checkpoints/<phase> "$(git stash create)"`.
- **Decisions:**
  - Take the recommended option and record it in the plan's Decisions log, so the user can review
    it later.
  - Ask the user only when a choice changes product behaviour in a way the plan doesn't cover.
- **Keep the plan's Status section current** at the end of each phase.

## Settled facts that save time

- A layer-list scene row is `NodeID(kind:, index: glTF node index)`, the same index as
  `MetalDraw.nodeIndex`. `GLTFDocument.id(ofNode:)` maps back.
- `MetalScene` is immutable and `Sendable`, and it keeps `asset` (GLTFKit2). `bounds(ofNode:)` and
  `fileCamera(at:aspect:)` already exist.
- The loader bakes world transforms, morph weights and skinning into vertex buffers at load.
  Picking and isolation therefore see the drawn shape. Animation (Phase 6) moves this to the GPU;
  see the research note.
- The selection AABB and floor/origin overlays live in `Renderer/MetalOverlays.swift`. They are
  soft depth-tested against the scene depth, and only when the orbit camera drew the model.
- `ModelView` handles input. A press in the top band (`contentInsets.top`) moves the window, and a
  drag orbits; shift-drag or middle-button drag pans.
- `ModelCanvasController` (owned by `ViewState.canvas`) outlives SwiftUI remounts. Route camera
  commands and new callbacks through it.
- Animation decisions: the window opens **paused at rest**. Play starts every non-conflicting clip,
  like Khronos. `KHR_animation_pointer` comes later (6.5). Thumbnails and Quick Look stay at rest.
- `KHR_node_visibility: false` nodes are shown as "Hidden in file". For now the eye can't override
  them, because the loader drops those draws.

## Done when

- Every ticket under `6tjaejue` is complete with a verified `--result`.
- Every row of the plan's coverage table behaves as written.
- `./scripts/dev.sh test` is green with the references unchanged, apart from new
  Khronos-rendered animation references.
- Each phase has been checked on screen.
- Report to the user: what landed, what was checked and how, the decisions you took, and what is
  left.
