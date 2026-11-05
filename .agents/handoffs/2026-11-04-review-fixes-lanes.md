# Handoff: review-fix epic `6ddtcd5k`, parallel lanes (2026-11-04 evening)

Paste everything below the line into the next agent.

---

You are continuing the review-fix epic `6ddtcd5k` in `/Users/mattias/dev/glb-preview` (macOS glTF
viewer, Swift/Metal). Read `AGENTS.md` first. Board CLI: `dex` (run it from the repo root in a
subshell: `(cd /Users/mattias/dev/glb-preview && dex …)`). Goal: implement every open leaf of
`6ddtcd5k`, test each one, review it, merge it to `main` and complete its ticket.

## State when this was written

- **Backlog is current.** Every leaf was re-audited against HEAD `1cbee80` and rewritten to be
  self-contained, with Why / Context (file:line) / Scope / Done when / Verification / Findings.
  Where the review had a red probe, the probe's Swift source is inlined in the ticket under
  **Red test (port)**. Read a ticket with `dex show <id> --full`. Source review:
  `.agents/reviews/2026-11-04-critical-code-review.md`.
- **Closed as already fixed by 1cbee80:** `vqnlmwn6` (M02/V04) and `0xfhivfq` (M01/M09).
- **Baseline:** `main` at `c2209d1` passes `./scripts/dev.sh test` (295 tests, 56 suites).
- **Another agent (Cursor) also commits to `main`.** Fetch the latest `main` and check
  `git log` before you merge.
- **Wave 1 (32 leaves) was started; 13 have commits and 1 is WIP** in 8 lanes, each a git worktree under
  `.claude/worktrees/agent-<id>` on branch `worktree-agent-<id>`. The lanes were told to commit
  the ticket in hand (or a `WIP:` commit) and stop. **None of it is merged into `main` yet.**
  All 32 leaves show as in progress on the board, including the ones nobody has worked on yet.
  Use `dex start <id> --force` to reclaim them.

| Lane | Worktree / branch suffix | Committed (unreviewed unless noted) | Left in lane order |
| --- | --- | --- | --- |
| frame | `a5e823905537b64a7` | `dd369b0` 713k1qc9, `1db6ce1` s1pmqv4t, which also carries zeif47se's test (zeif47se is fixed by 713k1qc9's `frame(box:)`) | none. Red was NOT observed on a clean tree; check it by reverting the fix locally |
| nav | `a7d341e667a696b14` | `a297866` yubkvjen, `92c41db` l6hjyzrn (selection no longer moves the camera; the glide is removed; `cancelRetarget()` is left as an empty stub because frame lane's `frame(nodeIndices:)` calls it, so delete both together when merging) | uszsoq3f, v0kt00mo |
| pick | `a508469251f22e84e` | `a0c64f1` itewlvcz, `00a2b0b` xwp69hz2 | 942cg24u, uvl074m9 |
| scene | `a0b03637bb79839f6` | `9bfdd58` fnc5cvpe (**reviewed and approved**) | 36u1efof, f017dg8b, rcyozymf, pvmm5n6u |
| anim | `acb5ed08acce59c3d` | `c30cbc7` lf1f6wdp, `15f3a7c` eixdin6y (the mismatch check is skipped when componentCount is 0) | 30wmzzbq, zd4wvy8e |
| play | `a7c751cc7082792ba` | `513f651` **WIP** 1ymkok59 | finish 1ymkok59, then fpzz07qc, cy74q46r, 2994l4eb, 93err3g9 |
| turn | `a1619b25df9a79d2d` | `08afa4a` yk0kezfd, `32cbb4a` 1bdfcj1o (input locked during export; new `TurntableExportHUD`; the GIF is now encoded in memory; no test yet for the captured pose; red not shown first) | dnguhcre (the pose is already captured; still needed: an explicit at-rest state instead of `time == 0`, plus its tests) |
| ui | `a07733f8b05707eee` | `0ce1d98` uq0fp1q2 | hvhg0plt, mtf17pxp, nkqi2m59 |

Lane notes from the implementers:
- **pick / xwp69hz2:** the BLEND alpha discard (`pickBlendAlphaThreshold = 0.05` in `pbr.metal`)
  also applies to the selection-ID/outline pass, so near-transparent texels no longer outline.
  Confirm that is wanted.
- **play / 1ymkok59:** every `_ = try await waitUntil` is now `#expect(...)`. The new HUD click
  tests are red because the synthetic-click helper gets an empty `accessibilityFrame`, and
  `animatedRowShowsAnimatedIndicatorOnlyWhenFlagged` can't find "Animated" under
  `.accessibilityElement(children: .combine)`. The morph live-weight case needs the Khronos
  `AnimatedMorphCube` sample; `TestFixtures.morph` has no animation.
- **scene / 36u1efof plan:** record in-scene nodes in the loader's collect walk, and visible nodes
  after the visit guard. Add `MetalScene.isEffectivelyVisible(node:)`. Filter
  `overlayGizmoSegments` / `overlayVertices` and the highlight/hover boxes with it.
  `MetalOverlayOptions` needs `soloNodeIndices`.
- **ui / hvhg0plt plan:** the range's far end is the added row farthest from the previous
  primary. Add `ShapePreviewController.reset()`. Gate empties and joints with no geometry on
  non-degenerate bounds. `ViewState.reset()` clears `showsSceneGizmos` and `lastPick`.

**Environment gotchas (fix before running lanes again):**
- `TestModels/Khronos samples/` is gitignored, so a fresh worktree doesn't have it and the full
  suite fails with ~51 "Model missing" issues. Symlink it into each worktree before testing:
  `ln -s "/Users/mattias/dev/glb-preview/TestModels/Khronos samples" "<worktree>/TestModels/Khronos samples"`.
- Concurrent `xcodebuild`s across worktrees hit "build.db is locked", and once compiled another
  worktree's sources. Run at most 4–6 lanes, keep each lane's DerivedData separate (it is, by
  branch), and never leave a background build running.

Start by checking each lane:

```bash
cd /Users/mattias/dev/glb-preview
for w in .claude/worktrees/agent-*; do echo "== $w"; git -C "$w" log --oneline main..HEAD; git -C "$w" status --short; done
```

Commits are named `<sentence>. (<ticket id>)`. A `WIP:` commit is unfinished, so don't merge it.
A dirty worktree with no commit is unfinished work. Either finish it in that worktree or discard it.

**Wave 2 (not started, must wait for wave 1 to merge):** these touch the same core files.
- `i8adt801` publishes posed node worlds to overlays, bounds and gizmos. Do it after
  frame + scene + anim.
- `eofgfd0l` reuses render targets with a 3-deep ring and stops blocking `waitUntilCompleted`.
  Do it after pick.
- `hi4csl96` fixes X-ray order, Mask, transmission and clay. It touches `pbr.metal`; watch the
  pixel tests.
- `e19dy2kk`, then `oyucq3um`, then `8f8oz49g`, then `dot2by1p` all edit
  `MetalSceneLoader.append`. Run them in one lane, in that order, after scene.

## How to run a lane

The implementer brief is in this file under "Lane brief" below. Give each implementer that brief
plus its ticket list. Per the user's preference, implementers are `task-implementer` on Haiku at
medium effort with `isolation: "worktree"`. You review and fix what they miss.

**Hard lesson from this run:** Haiku lanes backgrounded their builds and then spawned hundreds of
`sleep`/`while kill -0`/`until grep` watcher shells, pushing the load to about 38. The brief now
forbids it: tests run in the foreground with Bash timeout 600000 ms. Run at most **4–6** lanes at
once. A cold build per worktree takes about 10 min under load; incremental builds are fast.
If watchers pile up anyway, kill only the `eval '(until|while|for i|sleep)` shells and orphaned
`sleep`s, never `xcodebuild`.

## Review → merge → complete (you own this)

For each finished leaf commit:
1. Read the diff (`git -C <worktree> show <sha>`) against the ticket's Done-when list. Check that
   the regression test really asserts the bug (red before, green after), that nothing in
   `TestModels/References/` changed, and that no existing test was weakened.
2. Merge into `main` in the main checkout, either one lane branch at a time
   (`git merge --no-ff worktree-agent-<id>`) or by cherry-picking approved commits. Resolve
   conflicts by hand. `ModelView.swift`, `MetalRenderer.swift`, `ViewState.swift`,
   `CanvasRegion.swift` and `ModelCanvas.swift` are shared hot spots. Run
   `git branch --show-current` before you commit.
3. Run `./scripts/dev.sh test` on `main` after each merge. It must be green, with no reference
   images regenerated.
4. For UI-visible leaves (navigation, HUD, readout, gizmo, hover), check the app on screen:
   `./scripts/dev.sh run <fixture>`. AGENTS.md says what the logs must show, and the memory notes
   say to verify yourself and not ask the user.
5. `dex complete <id> --result "<what changed, test names>" --commit <sha-on-main>`. Complete an
   L1 when all of its leaves are done.
6. Remove a merged worktree: `git worktree remove .claude/worktrees/agent-<id>`, then
   `git branch -d worktree-agent-<id>`. The user wants `main` to stay the only branch.

**Done when:** every leaf of `6ddtcd5k` is complete, or explicitly declined with the reason
recorded in its leaf. `main` is green, every worktree and branch is removed, and the work is
pushed only if the user asks.

## Lane brief (give to each implementer)

> You are in a git worktree of /Users/mattias/dev/glb-preview. Read `AGENTS.md`. Read each ticket
> with `(cd /Users/mattias/dev/glb-preview && dex show <id> --full)`; that is the only command you
> run in the main checkout. Never run a dex mutation. Edit and commit only in your worktree, and
> check that `git branch --show-current` is not `main`.
> Per ticket: write or port the regression test (from the ticket's **Red test (port)** block
> when it has one), see it fail, fix the bug, run the targeted tests
> `./scripts/dev.sh test -only-testing:GLTFInspectorTests/<Suite>`, then commit with
> `git add -A && git commit -m "<Imperative sentence.> (<id>)"`. After the last ticket, run the
> full `./scripts/dev.sh test`.
> Rules: run tests in the FOREGROUND with Bash timeout 600000 ms. Never run_in_background, never
> sleep, never poll loops. Never touch `TestModels/References/` or the thresholds. Never weaken
> tests. Stay inside each ticket's Scope. Don't launch the app. If a ticket is already fixed or
> can't be done as specified, note why and move on.
> Report (≤ 25 lines): per ticket id · sha · tests added · result · any Done-when item not met;
> then the full-suite line and your branch name.
