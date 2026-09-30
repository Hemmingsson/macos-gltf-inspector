# WebKit first-paint experiments

Shared ledger for speeding Quick Look and the first window paint on `webkit-renderer`.
Read this before proposing or implementing a change. Measure; do not assume.

Champion worktree: `/Users/mattias/dev/glb-preview/.worktrees/webkit-renderer`

How to run a wave (seed, isolate, parent-only bench, KEEP/REJECT):
[webkit-perf-experiment-loop.md](webkit-perf-experiment-loop.md).
First-GPU-frame research: `.agents/research/2026-09-30-first-gpu-frame.md`.

## How to run

```bash
cd /Users/mattias/dev/glb-preview/.worktrees/webkit-renderer
./scripts/webkit-first-paint-bench.sh --label LABEL
```

The script runs a **fresh test process** for `tiny` / `BoomBox` / `Corset` (`proc-cold`), then one
in-process `full` pass (`cold` = new host, warm WebKit; `warm` = reused host).

| Phase | What it is |
| --- | --- |
| `pageMs` | `WKWebView` + `viewer.html` + module/WASM + `configure` |
| `iblMs` | `setEnvironment` (HDR fetch + Khronos probe) |
| `loadMs` | Swift `load` wait (`parseMs` + `fitMs` + bridge) |
| `parseMs` | Page `loadGltf` |
| `fitMs` | Page `fitCamera` |
| `stillMs` | `renderStill` / `toDataURL` |
| `visibleMs` | page + IBL + load — QL / window first paint |
| `totalMs` | visible + still (thumbnail) |

Required fixtures: `tiny.glb`, `BoomBox.glb`, `Corset.glb`. Optional Downloads files are
bonus only — never KEEP on those alone.

Do not change the `wk-fp` line format. Parent benches; implementers do not.

## What the numbers mean

Two different “cold”s:

1. **Session-first** (no recent WebKit): page ~1170 ms + IBL ~660 ms + load ~20 ms →
   **`visibleMs` ~1850**. This is the spacebar after idle.
2. **Process-cold after WebKit XPC is warm** (what the script’s `proc-cold` records if you
   just ran tests): page ~220–460 ms + IBL ~50–70 ms + load 6–27 ms → **`visibleMs` ~300–530**.

Model parse is **not** the wait. Do not spend an experiment on mesh packing or
`loadGltf` micro-opts unless a large asset’s `parseMs` is the remaining wall.

Warm reuse (thumbnail path) is already 20–50 ms load. QL does **not** reuse a host today
(`PreviewViewController` builds a new `WebPreviewCanvas`).

## KEEP / REJECT

Default gate is **`proc-cold visibleMs`**. GPU-frame wave (EXP-011+) also gates on
**`proc-cold stillMs`** (first `renderStill` / first GPU frame). Same 12% / 15% rule.

- **KEEP** if BoomBox **and** Corset `proc-cold` on the **target clock** drop **≥12%** vs the
  control table for that clock, and tiny does not regress **>15%**.
- **REJECT** if a required asset regresses, the still is blank, or the win is only on tiny
  / only on `warm`.
- **INCONCLUSIVE** if under 12% or a single noisy run (parent may rebench once).
- One change per experiment. Do not combine hypotheses.
- Do not retry a **Must not retry** row unless the approach is materially different.

Correctness: still PNG must stay a lit model. Do not add a second `viewer.html`.

## Baseline

Machine: MacBook Pro, 2026-09-30. Script `--label control`.
Raw: `/tmp/glb-preview-webkit-fp-bench/20260930-101155-control.log`

Session-first (earlier same morning, first host in a long-idle process):

| asset | page | ibl | load | parse | visible |
| --- | ---: | ---: | ---: | ---: | ---: |
| tiny.glb | 1174 | 658 | 22 | 20 | **1853** |

Script `proc-cold` (WebKit XPC already warm from the previous suite):

| asset | page | ibl | load | parse | fit | still | visible |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| tiny.glb | 456 | 69 | 6 | 5 | 1 | 139 | **530** |
| BoomBox.glb | 239 | 56 | 27 | 26 | 1 | 217 | **322** |
| Corset.glb | 220 | 52 | 23 | 23 | 0 | 196 | **296** |

In-process `cold` median (new host, warm process — second window):

| asset | page | ibl | load | visible |
| --- | ---: | ---: | ---: | ---: |
| tiny.glb | 82 | 52 | 5 | 139 |
| BoomBox.glb | 88 | 50 | 18 | 157 |
| Corset.glb | 113 | 59 | 28 | 200 |

`warm` load: tiny 6 / BoomBox 21 / Corset 31.

### After KEEP EXP-002 (now in champion)

`--label KEEP-002` raw `/tmp/glb-preview-webkit-fp-bench/20260930-102419-KEEP-002.log`.
`iblMs` is 0. First script process (closest to session-first): tiny **visible 661** (page 643)
vs old session-first **1853**.

| asset | page | ibl | load | visible | vs control |
| --- | ---: | ---: | ---: | ---: | ---: |
| tiny.glb | 643 | 0 | 18 | **661** | −64% vs session-first 1853 |
| BoomBox.glb | 229 | 0 | 32 | **261** | −19% vs 322 |
| Corset.glb | 209 | 0 | 23 | **232** | −22% vs 296 |

New KEEP gate uses this table as control. Remaining wall is **`pageMs`**.

## Open hypotheses (not yet measured)

Pick **one**. Prefer the phase that still dominates `visibleMs`.

Remaining wall after KEEP EXP-002: **`pageMs`** (still ~200–340 ms proc-cold, ~1170 ms session-first).
IBL is off the first-paint path (`iblMs` ≈ 0). First frame is key+fill until HDR lands.

### After KEEP EXP-010 (minified our module, now in champion)

`--label EXP-010` raw `/tmp/glb-preview-webkit-fp-bench/20260930-105059-EXP-010.log`.
Module **6.1 MB → 3.2 MB** (esbuild of the 2026-08-24 vendor, not the older npm 730 KB).

| asset | page | visible | vs KEEP-002 |
| --- | ---: | ---: | ---: |
| tiny.glb (first process) | 455 | **478** | −28% vs 661 |
| BoomBox.glb | 216 | **235** | −10% vs 261 |
| Corset.glb | 188 | **211** | −9% vs 232 |

QL also: cached Finder icon as first pixels (EXP-008) + `loadView` prestart (EXP-009).

### Lane A — page / JS / WASM (`pageMs`)

- Official npm 1.1.0 (730 KB) was **REJECT** — older dated bundle, `stillMs` doubled.
- Further Khronos tree-shake of *our* 3.2 MB minify (drop interactivity) is still open.
- EXP-005 stub KTX/Draco **combined with** the minified module.
- Named *empty* data store is still open; `.default()` is banned.

### Lane B — IBL

- ~~Load the model first; apply HDR after the first frame~~ **KEEP EXP-002** (in champion).
- Smaller / prefiltered environment for first paint — only if first-frame key+fill looks
  wrong; do not put HDR back on the `visibleMs` path.

### Lane C — host / QL path (process reuse)

- Reuse one `WebRendererHost` in the Quick Look extension like `ThumbnailProvider` does.
  EXP-003 implemented this; **REJECT** on the first-paint gate (proc-cold unchanged).
  Still worth retrying as a *second-open* win after measuring a living QL process.
- ~~Start the page (`host.start`) before / while the file URL is applied~~ **KEEP EXP-009**.
- Unhide the canvas after `load` without waiting on later look commands.
- `preserveDrawingBuffer: false` in `.live` — only if you have a reason it affects
  context create (`pageMs`).

### Lane D — first GPU frame (`stillMs` / live `firstFrameMs`)

Wave started 2026-09-30. Research:
`.agents/research/2026-09-30-first-gpu-frame.md`. Loop:
[webkit-perf-experiment-loop.md](webkit-perf-experiment-loop.md).

Old `wk-fp-001`…`010` worktrees removed (KEEP already in champion / REJECT recorded).
Wave `wk-ff-011`…`016` finished: **all REJECT** on `stillMs`. Trees removed after
the ledger rows. Next GPU-frame bets must delete work that is *on* `stillMs`
(PNG/readback split, or a profiled `renderer.init` cut), not flags that take a
slower fallback.

Target clock is **`proc-cold stillMs`** (still-mode first `renderStill`). Do not KEEP
on `visibleMs` for this lane.

### GPU-control (champion, 2026-09-30)

`--label GPU-control` raw `/tmp/glb-preview-webkit-fp-bench/20260930-112414-GPU-control.log`.
IBL already off `visibleMs`. `stillMs` includes first GPU frame + PNG (+ IBL join race).

| asset | page | load | still | visible |
| --- | ---: | ---: | ---: | ---: |
| tiny.glb | 815 | 20 | **201** | 835 |
| BoomBox.glb | 250 | 27 | **238** | 277 |
| Corset.glb | 188 | 32 | **243** | 221 |

KEEP on this lane: BoomBox still ≤209 **and** Corset still ≤214 (−12%), tiny still ≤231 (+15% max).

## Attempts

| id | hypothesis | phase targeted | result | visibleMs BoomBox / Corset | notes |
| --- | --- | --- | --- | --- | --- |
| EXP-001 hl0gq4ya | Defer KTX/Draco via peek JSON + inject scripts | pageMs | **REJECT** | 299 / 325 vs 322 / 296 | BoomBox −7% (under 12%). Corset +10%, tiny +19%. Peek+parse raised Corset `loadMs` 23→55. [impl](a49a515) `.worktrees/wk-fp-001` |
| EXP-002 azrebgcx | First `setEnvironment` is bookkeeping; IBL after `load`; key+fill until probe | iblMs | **KEEP** | 230 / 234 vs 322 / 296 | BoomBox −29%, Corset −21%, tiny −34%. `iblMs` 0. `renderStill` still joins IBL. Landed in champion. [impl](4085dc1) |
| EXP-003 2567vgp6 | Process-wide shared live `WebRendererHost` for QL remounts | host reuse | **REJECT** | n/a (still `proc-cold` is a new host) | Code looks sound; first spacebar unchanged. Not banned — retry as second-open measurement. [impl](e586f6a) `.worktrees/wk-fp-003` |
| EXP-004 rawuzmgt | Stream scheme handler in 64 KB `FileHandle` chunks | pageMs TTFB | **REJECT** | 288 / 262 vs 261 / 232 | BoomBox +10%, Corset +13%. Extra IPC did not beat one slurp. |
| EXP-005 mabigbaj | Stub KTX/Draco; `new ResourceLoader`; inject on decode miss (no peek) | pageMs WASM | **REJECT** | 247 / 208 vs 261 / 232 | BoomBox −5%, Corset −10%. Right direction, under 12%. Not banned. |
| EXP-006 i7yukaxc | `WKWebsiteDataStore.default()` instead of nonPersistent | pageMs compile cache | **REJECT** | 795 / 293 vs 261 / 232 | First process slower (store bring-up). Do not retry `.default()`. |
| EXP-007 oa8l82ii | Official npm `@khronosgroup/gltf-viewer@1.1.0` module (730 KB) | pageMs | **REJECT** | 249 / 230 vs 261 / 232 | Under 12%. `stillMs` ~2×. Older 2024-10-01 build vs our 2026-08-24 vendor. |
| EXP-008 rldcvxqt | Cached Finder icon under live canvas (no `QLThumbnailGenerator`) | perceived QL | **KEEP** | n/a (still bench unchanged) | Cache miss / generic UTI icon → no placeholder. Landed. |
| EXP-009 i9pqfh3a | Prestart live host in QL `loadView` | pageMs overlap | **KEEP** | n/a (overlap, not fewer bytes) | Same WKWebView for `preparePreviewOfFile`. Landed. |
| EXP-010 (parent) | esbuild minify of *our* 6.1 MB module → 3.2 MB | pageMs | **KEEP** | 235 / 211 vs 261 / 232 | BoomBox −10%, Corset −9%, tiny first-process −28% (661→478). Same renderer. Landed. |
| EXP-011 8f81043 | Skip first-bind `generateMipmap` | stillMs | **REJECT** | 239 / 304 vs 238 / 243 | BoomBox flat. Corset +25%. Tiny 174 vs 201. [GPU-control](file:///tmp/glb-preview-webkit-fp-bench/20260930-130811-EXP-011.log) |
| EXP-012 ae5fe23 | `internalMSAA = 0` | stillMs | **REJECT** | 322 / 279 vs 238 / 243 | Both slower. Tiny 175. |
| EXP-013 0a563dc | `floatingPointFramebuffer = false` | stillMs | **REJECT** | 294 / 365 vs 238 / 243 | 16F off is slower (likely a worse blit path). |
| EXP-014 00359ea | `maxAnisotropy = 1` | stillMs | **REJECT** | 258 / 253 vs 238 / 243 | Under the noise floor, slightly worse. |
| EXP-015 1f42b13 | Skip unused first-init FBO farm | stillMs | **REJECT** | 325 / 411 vs 238 / 243 | Vendor slice made first frame worse. Retry only with a proven-smaller `renderer.init`, not this patch. |
| EXP-016 5807e33 | Skip first-frame fullscreen tonemap blit | stillMs | **REJECT** | 541 / 582 vs 238 / 243 | Still-mode first frame *is* `renderStill`; skipping tonemap there doubled `stillMs`. Do not retry this still-path skip. |

## Must not retry

- Peek the whole GLB/JSON before `loadGltf` to decide KTX/Draco. The peek cost ate the
  page save on Corset/tiny. A stub-globals / decode-miss inject is a different family.
- Stream the renderer bundle through `WKURLSchemeTask` in 64 KB chunks. Worse than slurp.
- `WKWebsiteDataStore.default()` for compile cache. First-process `pageMs` got worse.
- Replace our vendor module with official npm 1.1.0 `dist/gltf-viewer.module.js`. Older
  dated build; `stillMs` doubled. Minify *our* file instead (KEEP EXP-010).
- `internalMSAA = 0` or `floatingPointFramebuffer = false` as a `stillMs` play
  (EXP-012/013). Measured slower on BoomBox and Corset.
- Skip the fullscreen tonemap blit on still-mode `renderStill` (EXP-016). That
  *is* the first GPU frame in the bench; skipping it made `stillMs` ~2×.

## Rules for implementers

1. Read this file. Work only in your assigned isolated worktree.
2. One hypothesis, one change family. Smoke-build. Leave a `perf:` commit. Do not bench.
3. Do not merge into `webkit-renderer`. Do not edit this ledger (parent updates it).
4. Do not add a second HTML page. Do not touch RealityKit convert for pixels.
