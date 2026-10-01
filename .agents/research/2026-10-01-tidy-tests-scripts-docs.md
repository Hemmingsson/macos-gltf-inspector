# Tidy: tests, scripts, docs, project config (non-product Swift)

Date: 2026-10-01 · Worktree `next-main` @ `b29ad5b` · Read-only survey. No product code was changed.
Evidence is `path:line` in this worktree unless marked otherwise. Test timings come from the last
`dev.sh test` xcresult (`/tmp/GLTFInspector-next-main-dd/Logs/Test/Test-GLTFInspector-2026.10.01_12-52-21-+0200.xcresult`):
337 cases (329 passed, 8 skipped), **45.7 s summed** case time.

## Answer first

1. **Seal bug (confirmed).** `scripts/dev.sh:52-53,57-58` copies the DerivedData app and then deletes
   `Contents/PlugIns/GLTFInspectorTests.xctest`. That xctest is already inside the outer seal. After
   any `dev.sh test` in the same DerivedData, the next `xcodebuild build` re-signs the app *with* the
   xctest listed in `_CodeSignature/CodeResources` (checked: 1 hit). Deleting it breaks the seal:
   `codesign --verify --deep --strict .build/glTF Inspector.app` gives "a sealed resource is missing or
   invalid". The DerivedData original passes the same check. You can't avoid the injection: the tests
   are hosted (`TEST_HOST`/`BUNDLE_LOADER`, `project.yml:448-449`) and `@testable import GLTFInspector`
   (13 files), so Xcode puts the bundle in the host's `PlugIns`. **Smallest fix:** stop deleting it
   and add a `codesign --verify --deep --strict` gate after each copy. The xctest is inert there,
   because pluginkit registers only `.appex`. Alternative if `/Applications` must stay test-free:
   delete, then re-sign the outer bundle only, with `codesign --force --sign "<Authority from codesign -dvv>"
   --preserve-metadata=identifier,entitlements,requirements,flags,runtime`. A separate DerivedData
   for installs also works, but it doubles build time, so it is not recommended.
2. **The test bundle embeds a second `DesignSystem` and `PreviewUI`.** `project.yml:458-459` has no
   `embed: false`, so `GLTFInspectorTests.xctest/Contents/Frameworks/` contains `DesignSystem.framework`
   and `PreviewUI.framework` (checked). The host already embeds both. That means two copies of each
   module in one process. Fix: add `embed: false` to both.
3. **Benches run in every `dev.sh test`.** They take **13+ s of the 45.7 s** summed time and include
   wall-clock asserts. They also hard-code `/Users/mattias/...` paths.
4. **Docs contradict the code.** README says WebKit draws everywhere and claims "preferences plist"
   settings. AGENTS points at a nonexistent `GLBPreview/`, `.cursor/plans` and DerivedData path.
   `docs/README.md` still describes the pre-split RealityKit pipeline. `project.yml` comments mention
   "prepare".
5. **Agent tooling is broken or dead.** The `.claude/agents/*` symlinks are dangling in every worktree.
   The Bash PreToolUse hook guards a `load-bench.sh` / `LoadTimeBenchTests` that exists nowhere,
   including on `main`.

## Findings → chunks (ranked; each ≤ 1–2 h, files disjoint unless noted)

### C1 — Install/proof scripts: seal fix + worktree correctness (bug, do first)

Files: `scripts/dev.sh`, `scripts/build.sh`, `scripts/proof.sh`, `scripts/archive.sh`.

| # | Evidence | Why | Change |
|---|---|---|---|
| a | `scripts/dev.sh:51-59` | Seal broken after test+install (see Answer 1) | Drop both `rm -rf …xctest`. After each `cp -R`, run `codesign --verify --deep --strict "$dst"` (fails loudly). Optional: use `ditto` instead of `cp -R` to keep xattrs. |
| b | `scripts/build.sh:32,38-41` + `scripts/lib/dev-env.sh:23-27` | In a worktree, `dev.sh install` writes only `.build/`. `build.sh` then `open`s and verifies the **stale** `/Applications` app from `main`. | When `INSTALL_KIND=worktree`, either refuse ("ship check is main-only") or open/verify `$LOCAL_APP` (`verify.sh` hard-codes `/Applications`, `scripts/verify.sh:10`). |
| c | `scripts/build.sh:21-23,32-36` | `--install-only` is exactly `dev.sh install`. VS Code already calls `dev.sh install` (`.vscode/tasks.json:6`). | Delete the flag (AGENTS:73 mentions it). |
| d | `scripts/proof.sh:15-19` | Uses a fixed `/tmp/GLTFInspector-dd` (not the branch DD) and skips `xcodegen generate`, so it can run a stale project. `GLB_PROOF_PNG` (`:9`) never reaches the test: `xcodebuild` does not forward env (stated in `scripts/regenerate-pixel-references.sh:13-15`). A custom value makes the script fail its own check. The qlmanage step (`:27-32`) hangs headless (user memory "qlmanage hangs headless"). | Call `"$ROOT/scripts/dev.sh" test -only-testing:GLTFInspectorTests/StillRenderProofTests`, drop the env override, and drop or flag-gate the qlmanage step. |
| e | `scripts/archive.sh:72,159-160` | Archive never builds the test target, and `rm` followed by `--verify` would hit the same seal bug if it did. The line is dead and misleading. | Replace with `[[ ! -e …xctest ]] \|\| { echo "test bundle in archive" >&2; exit 1; }`. |

Risk: low. Verification: run `dev.sh test` (puts the xctest into DD), then `dev.sh install`, then
`codesign --verify --deep --strict ".build/glTF Inspector.app"` prints nothing. `./scripts/proof.sh`
writes `/tmp/GLTFInspector-proof.png`. `bash -n` on every touched script. Δ ≈ −15 / +10 lines.

### C2 — Benches out of the default suite; retire the WebKit experiment kit

Files: `GLTFInspectorTests/WebKit/RendererTimingBenchTests.swift`, the two bench tests in
`GLTFInspectorTests/WebKit/WebRendererControlsTests.swift:338-383`, `scripts/webkit-first-paint-bench.sh`,
`scripts/seed-webkit-fp-exp.sh`, `docs/webkit-perf-experiment-loop.md`, `docs/webkit-first-paint-experiments.md`.

- `RendererTimingBenchTests.swift:24` is ungated. It runs on every `dev.sh test` (4.2 s). It hard-codes
  `/Users/mattias/dev/glb-preview/TestModels/Khronos samples` (`:87`). That is the main checkout, not
  this worktree, and other machines fail it. `/Users/mattias/Downloads` (`:88`) adds optional assets.
  It records an Issue for "required" BoomBox/Corset (`:93-100`). It reads `WK_FP_MODE` env (`:115`),
  which `xcodebuild` never forwards. Fix: gate it with `.enabled(if:)` on the request file the script
  already writes (`/tmp/glb-preview-webkit-fp-bench/request`, script `:35-37`), or use a repo sentinel
  like `LookProbeGate` (`CrossRenderer/LookProbeTests.swift:30-36`). Use `TestModels.khronosDirectory`.
  Drop Downloads and the env branch.
- `WebRendererThumbnailPathTests.recordsFolderScaleStillTiming` (`WebRendererControlsTests.swift:351-383`)
  is the **second-slowest case (8.8 s)**: 100 stills plus 12 cold hosts. It asserts `warmMs/100 < 5000`.
  `recordsSingleFileStillTiming` (`:339-349`) asserts `ms < 15_000`, which is wall-clock and flaky under
  parallel load. Move both into the gated bench file as print-only.
- `scripts/seed-webkit-fp-exp.sh` refuses to run outside a `*/webkit-renderer` worktree (`:14-17`) and
  copies a "dirty champion". It is dead on `next-main`. Delete it.
- The experiment docs (301 lines) describe a champion at `.worktrees/webkit-renderer`
  (`webkit-first-paint-experiments.md:6`, `webkit-perf-experiment-loop.md:6,37-38`). Keep the ledger's
  **"Must not retry"** table (`webkit-first-paint-experiments.md:203-214`) and the clock table by folding
  them into `docs/pipeline-web-renderer.md` §"Measured and not adopted" (`:171`). Delete the loop doc and
  the per-EXP attempt table, or move both under `docs/archive/`. **User decision:** retire the loop entirely?

Risk: low (no product change; coverage of the 15 s/5 s thresholds is lost, which is intended).
Verification: `dev.sh test` shows neither bench running (case count −3). `./scripts/webkit-first-paint-bench.sh`
still prints a `wk-fp` median table. Δ ≈ −330 lines (seed 32, loop doc 80, ledger ~150, test paths/env ~30,
asserts), default suite −13 s summed.

### C3 — WebKit tests: remove timing sensitivity (after C2; shares `WebRendererControlsTests.swift`)

Files: `GLTFInspectorTests/WebKit/WebCanvasControllerTests.swift`, `WebRendererHostTests.swift`,
`WebRendererControlsTests.swift` (non-bench part), new `GLTFInspectorTests/WebKit/WebKitTestSupport.swift`.

- **Real race:** `lostContextRestartsThePageOnceThenFails` (`WebCanvasControllerTests.swift:94-110`)
  sleeps 100 ms, then calls `settledPhase`, which waits only *while* `.loading` (`:19`). Under load the
  `contextlost` event can arrive after 100 ms. In that case the phase is still `.ready`, the first
  `#expect` passes vacuously, and the second `.failed` expectation flakes. Fix: wait until
  `phase != .ready` (bounded), then wait for settle. Drop the sleeps.
- Per-call timeouts in tests use the product default of 15 s (`RendererWebKit/WebRendererHost.swift:90`)
  or 8 s (`WebRendererHostTests.swift:156`). Swift Testing runs suites in parallel by default
  ([Parallelization.md](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Testing.docc/Parallelization.md)),
  so a dozen WKWebView pages and both pixel-diff suites contend for the GPU. Add one test factory,
  `WebKitTest.stillHost(size:)`, with a 60 s budget. It replaces `makeStillHost` (`WebRendererHostTests.swift:75`)
  and the inline `WebRendererHost(…)` constructions. Keep the deliberate 1 ms / 300 ms timeout tests
  (`WebCanvasControllerTests.swift:118,141`). They are deterministic because the call can never answer.
- Optional: nest the page-backed suites under one `@Suite(.serialized)` parent, declared in extensions,
  so at most one page renders at a time. `.serialized` "is recursively applied" to sub-suites (same doc).
  Measure the wall-clock cost first. The pixel-diff suites are already `.serialized`
  (`PixelDiffWebKitTests.swift:136`).

Risk: low–medium (serializing may lengthen wall time). Verification: run
`dev.sh test -only-testing:GLTFInspectorTests/WebCanvasControllerTests` 5× while another `dev.sh test`
runs. 0 failures. Δ ≈ −20 / +30.

### C4 — `project.yml`: embed fix + remove no-op settings + templates

File: `project.yml` (only).

- **Behaviour fix:** `:458-459` → `embed: false` for `DesignSystem` and `PreviewUI` (Answer 2).
- **No-op settings.** I confirmed them with `xcodebuild -showBuildSettings` on an un-overridden target
  (DesignCatalog). Release defaults are `ARCHS = arm64 x86_64` (= `ARCHS_STANDARD`), `ONLY_ACTIVE_ARCH = NO`
  and `ENABLE_TESTABILITY = NO`. Debug default is `ENABLE_TESTABILITY = YES`. So these lines can go:
  `Release: ARCHS/ONLY_ACTIVE_ARCH` ×6 (`:73-75,92-94,151-153,185-187,222-224,314-316`),
  `Debug: ENABLE_TESTABILITY: YES` ×4 (`:149-150,183-184,220-221,312`) and `Release: ENABLE_TESTABILITY: NO` (`:318`).
  `SWIFT_OBJC_BRIDGING_HEADER: ""` ×6 (`:70,88,116,146,180,217`) can go too: no project-level header is
  set, so empty is the default. `deploymentTarget: "26.0"` (`:61`) repeats `options.deploymentTarget` (`:4-5`).
- **Duplication.** The four extension-safe frameworks share `GENERATE_INFOPLIST_FILE/DEFINES_MODULE/APPLICATION_EXTENSION_API_ONLY`.
  `PreviewExtension` and `ThumbnailExtension` have identical entitlements, deps and settings
  (`:341-436`, about 95 lines). Use XcodeGen `targetTemplates` (`ExtensionSafeFramework`, `QuickLookAppex`)
  or YAML anchors.
- **Stale comments:** `:155` "→ prepare → convert" (there is no prepare pass;
  `docs/pipeline-gltf-to-realitykit.md:13`). `:408` "SPIKE:" duplicates the fuller comment at `:359-360`.

Risk: low if verified by a settings diff. Verification: before/after
`xcodebuild -showBuildSettings -scheme GLTFInspector -configuration {Debug,Release}` for every target,
diffed (only expected lines differ). `ls …/GLTFInspectorTests.xctest/Contents/Frameworks` is empty.
`dev.sh test` is green. `./scripts/archive.sh --preflight`. Δ ≈ −90 lines.

### C5 — Test helpers / fixtures dedupe (root + RealityKit test files only)

- `testNode(index:name:children:)` is byte-identical in `HostSidebarModelTests.swift:90` and
  `RealityKit/HostSidebarModelOverlayTests.swift:133`. Move one copy into a shared test file.
- `morphTriangleGLB()` appears twice (`RealityKit/MorphSkeletonTests.swift:199`, `RealityKit/MorphConvertTests.swift:18`).
  They are the same mesh, and one adds a weights clip. Make one builder with `withWeightClip: Bool` in `TestGLBFixtures.swift`.
- GLB builders live at file scope in a test file: `SessionDocumentTests.swift:149-430` (`writeTempTwoSceneGLB`, …)
  is used by `RealityKit/SessionDocumentConvertTests.swift`. Move them to `TestGLBFixtures.swift`
  (AGENTS already names that the home for GLB builders).
- `RealityKit/StillRenderProofTests.swift:16-26,51-60,82-89` repeats the turntable + `StillRenderer` setup
  three times. Extract `renderStill(url:size:background:)`. Its `GLB_PROOF_PNG` / `GLB_CUBE_PROOF_PNG`
  env reads (`:31,66`) and `PixelDiffManifest.swift:19` (`GLB_PIXEL_DIFF_OUT`) are dead under
  `xcodebuild` (see C1d). Make them constants.
- Stale comment `TestGLBFixtures.swift:198` says "so RealityPrepare does not rewrite them". RealityPrepare
  is gone, and AGENTS:116 says the LowLevelMesh path now takes *any* static accessor. Re-check whether the
  stride-16 trick still avoids the empty-UV readback. If it does not, the test using it may be vacuous.
- `scripts/testdata/README.md:21-36`: the "Used by" column drifts by hand. Drop it (grep is the truth).

Risk: low. Verification: `dev.sh test` is green with the same case count. Δ ≈ −120.

### C6 — Docs truth pass: AGENTS.md (shorter), README.md, docs/README.md, DESIGN.md (run last)

AGENTS.md is 206 lines / 18.8 KB. As an agent contract it should be about 100 lines and true:

- False or stale statements:
  - `:62-63`: "legacy `GLBPreview/`" does not exist, and "this worktree is throwaway" is wrong for `next-main`.
  - `:92-93`: "`xcodebuild` alone writes `/tmp/GLTFInspector-<branch>-dd`". Plain xcodebuild uses
    `~/Library/Developer/Xcode/DerivedData`. That path is `dev.sh`'s, from `scripts/lib/dev-env.sh:13`.
  - `:85`, and README `:61`: `/tmp/GLTFInspector-dd` is a third DD that only `proof.sh` shares.
  - `:132`: `.cursor/plans` is gitignored and absent in worktrees.
  - `:44`: lists `RendererTimingBenchTests` as a test (it becomes gated in C2).
  - `:72,190`: `build.sh` in a worktree (C1b).
  - `:119-120`: "EXP ledger … seam 11" refers to the C2 docs.
  - `:56`: "Proven on this branch" is a dated claim.
- Trim:
  - The layout table rows for `RendererWebKit` and `RendererRealityKit` (`:30-31`) enumerate the public API.
    Code is the truth, so keep one sentence each.
  - Move "Removing a renderer" (`:47-60`) and "RealityKit convert notes" (`:111-120`) into
    `docs/pipeline-gltf-to-realitykit.md` / a `docs/renderer-silos.md` and leave links.
  - Pitfalls 8 and 10 can link to the skills.
- README.md:
  - `:35-37` says "This branch (`webkit-renderer`) … RealityKit is not the on-screen renderer … host still
    converts". That is wrong: on `next-main` RealityKit is the default and WebKit runs no convert (AGENTS:16-19).
  - The mermaid diagram at `:88-89` shows convert feeding WebKit chrome.
  - `:99-100` says "extensions read the app's preferences plist". The code uses the App Group suite
    (AGENTS pitfall 5).
  - `:110` links `Vendor/web-renderer`, which is a dead link. The bundle is `RendererWebKit/web-renderer`.
  - The headline at `:8` says "in WebKit". **User decision** on product framing.
- `docs/README.md`:
  - `:10` "prepare → GLTFKit2 → Entity (inspector / fallback, not the canvas)" is wrong on both counts.
  - `:13` "goldens for the JavaScript renderer" is wrong; there are now goldens for both renderers.
  - Rows `:11-12` change after C2.
- `docs/decision-web-renderer.md:3-5` has status "the unused `PreviewScene` fallback". `PreviewScene`
  is the default canvas now. Add a dated status banner ("superseded by the renderer switch, see AGENTS")
  rather than rewriting the record.
- `DESIGN.md:38-39` says "one Khronos Sample Renderer in WebKit for the window, Quick Look, and Finder".
  That is now a switch. Rephrase to "the same renderer on every surface". **User decision** (principle text).
- Out of scope (product Swift comments), noted only: `DesignSystem/Tokens/DS+Color.swift:88,126` cite
  `PreviewUI.Theme`, which no longer exists. `DesignSystem/Tokens/DS.swift:12` cites `Shared/`.

Risk: none (docs). Verification: `git grep -nE "GLBPreview|GLTFInspector-dd|Vendor/web-renderer|preferences plist|webkit-renderer\)|prepare →"`
returns nothing outside `.agents/` and `docs/archive`. Every path cited in AGENTS exists (a quick
`grep -o '\`[A-Za-z/._-]*\`'` plus an `ls` loop). Δ AGENTS ≈ −90 lines, README ≈ ±15.

### C7 — Agent/editor hygiene (needs user OK for deletions)

Files: `.claude/agents/*`, `.claude/settings.json`, `.cursor/hooks*`, `.agents/agents/glb-load-*.md`,
`.gitignore`, `.vscode/launch.json`, `.vscode/tasks.json`.

- `.claude/agents/*.md` are git symlinks to `../../.cursor/agents/*.md` (`git ls-files -s` mode 120000).
  `.cursor/agents` is gitignored (`.gitignore:14`) and exists only in the main checkout, so **all 6 are
  dangling in every worktree**. The real files are tracked in `.agents/agents/`. Re-point them to
  `../../.agents/agents/` (as `.claude/skills → ../.agents/skills` already does).
- The `.claude/settings.json:9` PreToolUse(Bash) hook runs python3 on **every** Bash call to guard
  `scripts/load-bench.sh` / `LoadTimeBenchTests` (`.cursor/hooks/deny-parallel-load-bench.sh:24-25`).
  Neither exists on `next-main` or `main`. The `glb-load-*` agents (`.agents/agents/glb-load-*.md`) drive
  that same missing pipeline (`experiments/results`, `load-bench`). Delete the hook, `.cursor/hooks.json`
  and the 4 agents, or park them. **User decision.** `repository-reduction.md` (713 lines) and
  `repository-simplification.md` (581 lines) are large but self-contained. Leave them.
- `.gitignore`. These rules match nothing in either checkout (`git ls-files -o -i --exclude-standard`):
  `.zed/`, `.conductor/`, `.superpowers/`, `!.docs/`+`!.docs/**` (negation without a rule), `test-models/`,
  `.readme-preview.html`, `scripts/.cache/`, and the `Fixtures/` + `!PreviewUI/PreviewSupport/Fixtures/` pair
  (the cause of commit 3d2b374). Remove them.
  - `plans/` (`:28`) silently ignores `.agents/plans/`. The renderer-separation plan there is untracked.
    m-write-plan writes there. Make it `/plans/` or drop it.
  - Add `TestModels/Fixture Models/probes/RUN_LOOK_PROBES` (the sentinel from `scripts/testdata/run-look-probes.sh:8`;
    REGENERATE/MEASURE_NOISE are already listed).
  - Add `.agentree/` (untracked tool config on main).
  - `.atelier/`: track or ignore? **User decision.**
- `.vscode/launch.json:44-56,66-70`: the "WebKit + fixture" / "Attach WebKit" configs point at
  `.worktrees/webkit-renderer/.build/…`. The renderer is now a DEBUG launch argument
  (`GLTFInspector/RendererRouter.swift:35`). Replace them with the same `.build` app plus
  `"args": ["-GLTFRenderer", "webkit"]`. Delete the `dev: install webkit` task (`tasks.json:23-35`).
  The fixture pick-list (`launch.json:9-20`) duplicates `scripts/fixtures.manifest.json` and lacks `corrupt`.

Risk: low. Verification: `for f in .claude/agents/*; do test -e "$f"; done`, the agent list loads in a
fresh worktree session, `git status --ignored` shows no newly untracked files, and VS Code "Debug"
launches the WebKit window. Δ ≈ −150.

### C8 (optional, decision) — Look-probe kit

`CrossRenderer/LookProbeTests.swift` (529 lines, sentinel-gated), `scripts/testdata/make_look_probes.py` (198),
`run-look-probes.sh` (17) and 6 probe fixtures. Its job, calibrating `RealityLook` constants, is done
(`.agents/research/2026-09-30-look-probes.md`). It compiles on every run but never executes, so it can
rot at runtime unnoticed. Keep it if look recalibration is expected. Otherwise delete it (about −800 lines).

## Ordering and overlap

C1, C4, C5 and C7 are fully disjoint, so run them in parallel. C2 comes before C3 (both touch
`WebRendererControlsTests.swift`). C6 comes last because it documents the C1/C2 outcomes. C8 waits on
the user.

## Not issues (checked)

- Large binaries: the README images (3.3 MB in `assets/*.webp|png`) are referenced by `README.md`. The HDRs
  are bundled by `GLTFCore` (`project.yml:131`). The web-renderer bundle is checksummed by
  `scripts/vendor-web-renderer.sh`.
- The release chain (`release.sh` → `archive.sh` → `appcast.sh` → `sparkle-*.sh`, `rewrite-appcast-urls*`)
  is cohesive and exercised by `release.sh --preflight` (`:136-138`).
- `GLTFInspectorTests` root files import no renderer. Each `CrossRenderer/` file is `canImport`-gated, as AGENTS requires.
- `scripts/fixtures.manifest.json` is read by `GLTFInspector/DevLaunch.swift:25` and `scripts/lib/dev-env.sh:21`. Keep it.

## Unresolved

- Does `/Applications` on `main` need to be test-bundle-free? If yes, use the re-sign variant in C1a.
- Should the WebKit perf-experiment loop and the load-bench agent fleet be retired (C2, C7)?
- README / DESIGN product framing for a two-renderer build (C6).
