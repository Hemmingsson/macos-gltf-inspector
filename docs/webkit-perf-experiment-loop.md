# WebKit performance experiment loop

How to try one idea, measure it, and keep or throw it away. For an agent
about to run a wave — not a product tour.

Champion: `.worktrees/webkit-renderer`. Ledger: [webkit-first-paint-experiments.md](webkit-first-paint-experiments.md).
Research for the GPU-frame wave: `.agents/research/2026-09-30-first-gpu-frame.md`.

## Which clock

| You are speeding | Clock | Where it lives |
| --- | --- | --- |
| Spacebar / first window pixels | `visibleMs` | page + IBL + `load` (live `load` includes first `renderFrame`) |
| First **GPU** frame (the blank after parse) | `stillMs` (still bench) and live `firstFrameMs` | `renderStill` / live `renderFrame` |
| Finder thumbnail PNG | `totalMs` | visible + still |

Do not KEEP a GPU-frame change on `visibleMs` alone. Do not KEEP a page-compile
change on `stillMs` alone.

## One wave

```text
clean leftovers → research (one phase) → seed isolated trees → implement
(one change each, no bench) → parent benches sequentially → KEEP / REJECT
→ land KEEP in champion or delete the tree
```

1. **Clean.** Remove finished experiment worktrees (`exp/wk-ff-*` / `exp/wk-fp-*`)
   after the ledger row exists. `git worktree remove --force`, then `git branch -D`.
   Leave champion and unrelated chrome trees.
2. **Research.** One phase. Write `.agents/research/YYYY-MM-DD-short-slug.md`
   with Fact/Assumption and ranked **one-change** hypotheses. Do not implement
   in the research pass.
3. **Seed.** From the **dirty champion tree** (KEEP work is often uncommitted):

   ```bash
   cd /Users/mattias/dev/glb-preview/.worktrees/webkit-renderer
   ./scripts/seed-webkit-fp-exp.sh 011 "skip first-bind generateMipmap"
   ```

   That creates `.worktrees/wk-ff-011` on `exp/wk-ff-011` and copies champion
   including uncommitted files.
4. **Implement.** One hypothesis per tree. Smoke-build. `perf:` commit. **Do not
   bench. Do not edit the ledger.** No second `viewer.html`. No RealityKit pixels.
5. **Bench (parent only, one at a time):**

   ```bash
   cd /path/to/that/worktree
   ./scripts/webkit-first-paint-bench.sh --label EXP-011
   ```

   Required fixtures: `tiny.glb`, `BoomBox.glb`, `Corset.glb`.
6. **Decide.** Write the ledger row. KEEP lands in champion; REJECT trees are
   removed in the next clean.

## Gates

**Page / first paint (`visibleMs`)** — BoomBox **and** Corset `proc-cold visibleMs`
drop **≥12%** vs the current ledger control; tiny must not regress **>15%**.

**First GPU frame (`stillMs`)** — same 12% / 15% rule on `proc-cold stillMs`.
Still PNG must stay a lit model (PixelDiff / `TestModels/References`). A win
only on tiny or only on `warm` is REJECT.

**INCONCLUSIVE** if under 12% or a single noisy run. Rebench once, then decide.

## What implementers must not do

- Bench (`webkit-first-paint-bench.sh` / `RendererTimingBenchTests` as a decision).
- Edit the ledger or this loop doc.
- Combine two hypotheses.
- Retry a **Must not retry** row unless the approach is materially different.
- `WKWebsiteDataStore.default()`, official npm 1.1.0 module, peek-whole-GLB for
  KTX/Draco, 64 KB scheme streaming.

## After KEEP

Copy the change into champion (or merge the branch). Re-install to
`/Applications` only when Finder should use it. Update the ledger control table.
Delete the experiment worktree.
