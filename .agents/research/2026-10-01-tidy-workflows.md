# Tidy loop for glTF Inspector: methods, tools, stop criteria

Date: 2026-10-01 · Scope: research only · Repo: `next-main` worktree (~39k Swift LOC, 311 files, 29k non-test)

## Answer first

Run the loop as a **ratchet**, not as open-ended "improve the code" passes:

1. **Baseline once**: green `dev.sh test` (pixel-diff goldens included), then write tool baselines
   (Periphery, jscpd, SwiftLint metrics, build warnings, compile-time warnings, coverage).
2. **Waves in a fixed order**: delete → dedupe → hotspot tidyings → structural moves (Mikado or
   parallel change, only where needed) → docs match code.
3. **Each task is one named move** (Beck tidying or Fowler refactoring) on a scope you can name
   (a file, a type, or a clone pair). It is structure-only, its own commit, and about ≤300 changed
   lines.
4. **Gates**: per task, build plus affected tests. Per wave, the full test suite with **goldens
   frozen**, no new warnings or findings against the baselines, the architecture-invariant greps,
   and a review in a fresh context that only looks for behaviour changes.
5. **Stop** when the "done" checklist below passes, or after two consecutive waves that each
   produce fewer than 3 accepted tasks. Keep a won't-fix ledger so agents do not re-propose or
   undo earlier decisions.

Tools to add, all small: **Periphery** (dead code, unused imports, redundant `public`),
**SwiftLint** (used once as a metrics probe, not as a gate), **jscpd v5** (duplication), and
**Xcode built-ins** (`xcresulttool` warnings and compare, `-warn-long-function-bodies`,
`xccov`). Skip swift-format reformatting: it creates diff noise, and the repo has no style config.

## 1. Methods: what to take from each

| Source | Use in this loop |
| --- | --- |
| Beck, *Tidy First?* ([O'Reilly](https://www.oreilly.com/library/view/tidy-first/9781098151232/), [summary](https://www.workingsoftware.dev/summary-of-tidy-first-book/)) | Use the 15 tidyings as the task vocabulary: Guard Clauses, Dead Code, Normalize Symmetries, New Interface/Old Implementation, Reading Order, Cohesion Order, Move Declaration and Initialization Together, Explaining Variables, Explaining Constants, Explicit Parameters, Chunk Statements, Extract Helper, One Pile, Explaining Comments, Delete Redundant Comments. Rules to keep: tidyings go in separate commits or PRs from behaviour changes, batches stay small, and you stop tidying when the next tidy does not make a change easier. |
| Fowler catalog ([refactoring.com/catalog](https://refactoring.com/catalog/)) | The most relevant moves here: Remove Dead Code, Inline Function/Variable/Class, Remove Middle Man, Extract Function, Split Phase, Decompose Conditional, Replace Nested Conditional with Guard Clauses, Consolidate Conditional, Combine Functions into Transform, Introduce Parameter Object, Preserve Whole Object, Remove Flag Argument, Parameterize Function, Move Function/Field, Slide Statements, Split Loop, Replace Magic Literal, Encapsulate Collection. Prefer *Inline* and *Remove* over *Extract*, because extraction adds surface. |
| Mikado method ([mikadomethod.info](https://mikadomethod.info/), [Manning ch.1](https://manning-content.s3.amazonaws.com/download/3/558b9be-92a7-4ebf-90ba-c7fdd830aea7/MikadoMethod_CH01.pdf)) | Use it only for structural goals that break the build: try the naive change, record what breaks as prerequisite nodes, **revert**, then work leaves-first. This maps cleanly onto dex: the goal is the L1 ticket and the prerequisites are L2 tickets. A subagent attempt that fails gets reverted and turned into graph nodes, never patched forward. |
| Parallel change / strangler ([ParallelChange](https://martinfowler.com/bliki/ParallelChange.html), [StranglerFig](https://martinfowler.com/bliki/StranglerFigApplication.html)) | When you replace an API that has many callers (for example seam types in `PreviewUI/Seam/Models.swift`), expand first, then migrate callers in batches, then contract. Every step stays green, and the batches can run in parallel. |
| Characterization tests ([Feathers](https://en.wikipedia.org/wiki/Characterization_test)) | Before tidying a hotspot with low coverage, add tests that pin its *current* behaviour, oddities included, in a tests-only commit. The existing pixel-diff goldens and `GLTFValidatorCorpusTests` already characterize both renderers end to end. Treat them as frozen during the loop: if a golden fails, the tidy is wrong. |
| Ousterhout, *A Philosophy of Software Design* ([book](https://web.stanford.edu/~ouster/cgi-bin/book.php)) | The complexity symptoms are change amplification, cognitive load and unknown unknowns. The red flags work well as reviewer prompts: shallow module, information leakage, temporal decomposition, overexposure, pass-through method, repetition, special-general mixture, conjoined methods, comment repeats code, vague or hard-to-name names. **Caveat**: the `Engine*` adapters are deliberate seams (AGENTS.md), so "pass-through" there is accepted. Do not collapse seams to save lines. |
| Metz, [The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction) | When deduplicating, merge only clones that change for the same reason. Inlining a bad shared helper back into its callers is a valid tidy. |
| CodeScene hotspots ([docs](https://codescene.io/docs/guides/technical/hotspots.html)) | Rank work by churn × complexity. Most change lands in a small set of files, so spend effort there and leave the long tail alone. |
| Claude Code best practices ([docs](https://code.claude.com/docs/en/best-practices)) | Give the agent a pass/fail check. Use a separate fresh-context reviewer, not self-grading. Scope tasks narrowly. Use worktrees for parallel writers. After two failed corrections, start over with a better prompt. Tell reviewers to flag **only** correctness or requirement gaps, otherwise they push towards over-engineering. |
| LLM refactoring evidence ([arXiv 2411.04444](https://arxiv.org/abs/2411.04444), [arXiv 2602.21833](https://arxiv.org/abs/2602.21833)) | About 7% of LLM refactorings were unsafe (behaviour change or broken syntax), so test gates are mandatory. Naming the refactoring category in the prompt raised the success rate from 15.6% to 86.7%, which supports "one named move per task". Iterative LLM readability passes restructure first and then *stabilize*, so expect diminishing returns and stop on low yield rather than running a fixed count. |

## 2. Recommended loop

```
Wave 0  Baseline      tests green · write baselines · coverage map · hotspot list · won't-fix ledger (empty)
Wave 1  Delete        Periphery dead code → unused imports → redundant public → stale comments/docs
Wave 2  Dedupe        jscpd clones ≥70 tokens in prod code; merge only same-reason clones
Wave 3  Hotspots      top ~10 churn×complexity files; Beck/Fowler moves; characterize first if uncovered
Wave 4  Structure     only goals surfaced by 1-3; Mikado graph or parallel change; dex L1 + L2s
Wave 5  Docs          AGENTS.md / docs paths and symbols exist; no TODO without dex ref
Repeat 1→3 once (deletions expose new dead code), then evaluate stop criteria.
```

Roles: researcher (scan output → candidate tasks with a named move, scope and expected delta);
implementer (one task, own worktree, medium effort); reviewer (fresh context, diff only, asks
"could this change behaviour?"); integrator (serial merge, then the wave gate). Existing repo
agents fit these roles: `repository-cleanup-continue`, `repository-simplification`,
`task-implementer`, `code-reviewer`.

**Sizes**: one task is 1 move, ≤5 files and ≤300 changed lines (deletions can be bigger). Run up
to 3 parallel implementers, each on disjoint modules (for example GLTFCore | PreviewUI |
RendererWebKit). Do not run two tasks on the same file in one wave.

**Gates**

| When | Gate |
| --- | --- |
| Per task | `./scripts/dev.sh test -only-testing:GLTFInspectorTests/<affected suites>` plus a build of all targets, then the reviewer. Commit message `tidy(<move>): <scope>`. |
| Per wave | Full `./scripts/dev.sh test` with goldens untouched (`git diff --quiet TestModels/References`). `xcresulttool compare --build-warnings` shows 0 new warnings. The Periphery and jscpd baselines show 0 new findings. The invariant greps (§4) are clean. The metrics snapshot is ≤ the previous one. |
| Never | Regenerating pixel references, editing tests to make them pass (unless the task is "tests only"), mixing a tidy with a behaviour fix (log the fix as a separate dex ticket instead). |

**Convergence rules**: (a) Ratchet, so every metric is ≤ its baseline after each wave.
(b) Won't-fix ledger: a rejected finding gets `// periphery:ignore - <reason>` or a ledger line,
and agents must read the ledger before proposing. (c) A Mikado attempt that fails gets
reverted, never patched forward. (d) No-oscillation check: the reviewer rejects a diff that
reverses a change from an earlier wave.

## 3. Tool shortlist (exact commands)

Run everything from the worktree root after `xcodegen generate` (the `.xcodeproj` is
gitignored). `S=$TMPDIR/tidy` (or the scratchpad) holds outputs. Paths:
`SRC="GLTFCore RendererRealityKit RendererWebKit PreviewUI DesignSystem DesignCatalog GLTFInspector PreviewExtension ThumbnailExtension GLTFInspectorTests"`
(in zsh use `${=SRC}`). The vendored JS (`RendererWebKit/web-renderer/gltf-viewer.module.js`,
`libs/`, `Vendor/`) has no `.swift` files, but still exclude it from jscpd.

### Periphery: dead code, unused imports, redundant `public`

- **Install**: `brew install periphery` (3.8.0; release zip ~8.8 MB; no brew deps). **Status**:
  the upstream repository was archived on 2026-08-12 when the project went commercial
  ([periphery.pro](https://periphery.pro/a-new-chapter)). Homebrew marks the formula deprecated
  and will disable it on 2027-08-12. It still installs and works. Compatibility with Xcode 27 is
  **not verified**: run it once and check for index-store errors.
- **How it builds**: it runs `xcodebuild build-for-testing` with `COMPILER_INDEX_STORE_ENABLE=YES`
  for the given schemes. Test targets are therefore built, and test references count as uses.
- **Main scan**:
  ```bash
  periphery scan --project GLTFInspector.xcodeproj --schemes GLTFInspector DesignCatalog \
    --retain-codable-properties --retain-swift-ui-previews \
    --relative-results --write-results "$S/periphery-all.txt" \
    -- -destination 'platform=macOS'
  ```
- **Diagnostic scans**:
  - Add `--exclude-tests` to find code reachable only from tests. These are deletion candidates
    together with their tests, but need judgement.
  - Drop `--retain-swift-ui-previews` to find views and fixtures used only by `#Preview` (79
    files have previews).
  - Use `--schemes GLTFInspector` only to find DesignSystem parts used only by the catalog.
    Report these, do not auto-delete them.
- **Ratchet**: `--write-baseline .periphery-baseline.json` once, then
  `--baseline .periphery-baseline.json --strict`, which exits non-zero on new results. When a
  config is settled, run with `--verbose`, copy the `[configuration:begin]` YAML into
  `.periphery.yml`, and `periphery scan` uses it from then on.
- **Faster re-scan**: run `./scripts/dev.sh test COMPILER_INDEX_STORE_ENABLE=YES`, then add
  `--skip-build --index-store-path /tmp/GLTFInspector-next-main-dd/Index.noindex/DataStore`. Use
  one index store per worktree so parallel agents do not collide.
- **Expected false positives in this repo**:
  - Declarations used only in `#else` branches of `#if canImport(Renderer…)` or `#if DEBUG` (5
    files). Only the compiled branch is indexed.
  - Unused-import results in `RendererRealityKit`, which is mixed with Objective-C
    (`GLBDracoDecompressor`, found by class-name string).
  - Properties read only by synthesized `Equatable`/`Hashable` (45 files). Add
    `--retain-equatable-properties` if that is noisy.
  - Codable properties read only by synthesized code (15 files), which the main scan retains.
  - Anything reached by string from JavaScript or `UserDefaults` keys.
- **Not a problem**: `NSExtensionPrincipalClass`/`NSPrincipalClass` classes in Info.plist,
  Swift Testing `@Test`, `@main` and result-builder methods are retained automatically. Do
  **not** use `--retain-public`: the app is scanned together with its frameworks, so redundant
  `public` is a real signal and matches the minimal-public-API rule in AGENTS.md.
- **Suppress** with `// periphery:ignore - reason`. Superfluous ignores are reported by default,
  so stale suppressions surface on their own.
- Sources: [README](https://github.com/peripheryapp/periphery),
  [CHANGELOG](https://github.com/peripheryapp/periphery/blob/master/CHANGELOG.md).

### SwiftLint: one-off complexity and size metrics, not a gate

- **Install**: `brew install swiftlint` (0.65.1; arm64 zip ~28 MB, portable ~12 MB; no deps).
  Do not commit a `.swiftlint.yml`. Keep the config in `$S`:
  ```yaml
  # $S/metrics.yml
  only_rules: [cyclomatic_complexity, function_body_length, type_body_length, file_length, closure_body_length, function_parameter_count, nesting]
  cyclomatic_complexity: {warning: 10, error: 20, ignores_case_statements: true}
  function_body_length: {warning: 50, error: 100}
  type_body_length: {warning: 250, error: 400}
  file_length: {warning: 400, error: 800, ignore_comment_only_lines: true}
  closure_body_length: {warning: 40, error: 100}
  ```
- **Run**: `swiftlint lint --config "$S/metrics.yml" --reporter json --quiet --no-cache ${=SRC} > "$S/metrics.json"`.
  Pass paths positionally, because `included:` resolves relative to the config file. Defaults
  are 10/20, 50/100, 250/350 and 400/1000 ([rule docs](https://realm.github.io/SwiftLint/cyclomatic_complexity.html)).
- **Noise**: long SwiftUI `body` builders (`closure_body_length`) and switch-heavy mapping code
  (handled by `ignores_case_statements`).
- **Alternative unused-import check**: `swiftlint analyze --compiler-log-path build.log --only-rule unused_import`.
  It needs a *clean* build log, and Periphery covers the same ground.

### jscpd v5: duplication

- **Install**: none. `npx -y jscpd@5.4.0` fetches a prebuilt Rust binary (~36 MB, cached). Or
  `brew install jscpd`.
- **Run**:
  ```bash
  npx -y jscpd@5.4.0 ${=SRC} --format swift --min-tokens 70 --min-lines 6 \
    --ignore "**/web-renderer/**,**/Vendor/**" --reporters console,json --output "$S/jscpd" --no-tips
  ```
- **Variants**:
  - Add `--ignore-identifiers --ignore-literals` to find renamed (Type-2) clones.
  - Use `--complexity --reporters ai` for a cheap ranking of the most complex files.
  - For the ratchet, use `--baseline .jscpd-baseline.json --update-baseline` once, then
    `--fail-on-new-clones`.
- **Expected noise**: test fixtures and builders (`TestGLBFixtures.swift`, PixelDiff suites),
  `#Preview` bodies, and DesignCatalog pages. Report production clones separately from test
  clones. Source: [jscpd](https://github.com/kucherenko/jscpd),
  [CLI reference](https://github.com/kucherenko/jscpd/blob/master/docs/rust.md).

### Xcode built-ins (zero install)

- **Warnings**:
  ```bash
  ./scripts/dev.sh test -resultBundlePath "$S/base.xcresult"
  xcrun xcresulttool get build-results --path "$S/base.xcresult" --compact
  ```
  The second command gives the warning list. Per wave, run
  `xcrun xcresulttool compare "$S/wave.xcresult" --baseline-path "$S/base.xcresult" --build-warnings`.
  Filter out warnings from SPM checkouts (Sparkle, GLTFKit2, DracoSwift).
- **Compile-time hot spots** (the flag is unsupported and may change):
  ```bash
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
    -derivedDataPath /tmp/GLTFInspector-tidy-dd clean build -showBuildTimingSummary \
    OTHER_SWIFT_FLAGS='$(inherited) -Xfrontend -warn-long-function-bodies=150 -Xfrontend -warn-long-expression-type-checking=100' \
    2>&1 | tee "$S/timing.log"
  grep -E "took [0-9]+ms to type-check" "$S/timing.log"
  ```
  The project sets no `OTHER_SWIFT_FLAGS`, so the override is safe. Source:
  [CompilerPerformance.md](https://github.com/swiftlang/swift/blob/main/docs/CompilerPerformance.md).
- **Coverage map** (to decide where to add characterization tests first):
  ```bash
  ./scripts/dev.sh test -enableCodeCoverage YES -resultBundlePath "$S/cov.xcresult"
  xcrun xccov view --report --files-for-target <Target>.framework "$S/cov.xcresult"
  ```
- **swift-format** is bundled (`xcrun swift-format lint -r -p <dirs>`). It is optional as a
  measurement. Do not run `format -i` repo-wide mid-loop, because it buries the reviewable diffs.

### Hotspots: churn × size or complexity (git only)

```bash
git log --format= --name-only --no-merges -- '*.swift' | grep . | sort | uniq -c |
  while read c f; do [ -f "$f" ] && echo "$((c * $(wc -l < "$f"))) $c $(wc -l < "$f") $f"; done | sort -rn | head -15
```

For a better ranking, replace `wc -l` with the summed cyclomatic complexity per file from the
SwiftLint JSON. Caveat: the branch has a short history (219 commits) with many file moves, and
renames reset churn, so weight complexity more heavily. Snapshot today, by churn × lines:

1. `PreviewUI/Seam/Models.swift` (919 lines)
2. `PreviewUI/Settings/PreviewSettingsRoot.swift`
3. `GLTFInspector/Engine/EngineViewportController.swift`
4. `GLTFInspector/Engine/EngineSceneModel.swift`
5. `PreviewUI/Frame/ShellRootView.swift`
6. `RendererWebKit/WebPreviewCanvas.swift`
7. `RendererWebKit/WebRendererHost.swift`
8. `PreviewUI/Sidebar/OutlinerSection.swift`
9. `RendererRealityKit/Convert/RealityKitConvert.swift`

Size distribution: 42 files over 250 lines, 12 over 400, 5 over 600.

## 4. Stop criteria ("done" for this repo)

All of these hold on one commit, and two consecutive full scans produce no new task-worthy
findings:

1. **Behaviour**: `./scripts/dev.sh test` is green, including `PixelDiffWebKitTests`,
   `PixelDiffRealityKitTests` and `GLTFValidatorCorpusTests`. `TestModels/References/` is
   byte-identical to the baseline commit.
2. **Warnings**: 0 compiler warnings from first-party targets (from `xcresulttool` build
   results).
3. **Dead code**: Periphery main scan has 0 results. Every kept item carries a
   `periphery:ignore - reason` and there are no superfluous ignores. There are 0 redundant
   `public` declarations beyond the documented API in AGENTS.md.
4. **Duplication**: jscpd finds no production clone of 100 tokens or more. Smaller ones need a
   ledger entry, and the overall duplication rate is ≤ the baseline.
5. **Size and complexity**:
   - No function above cyclomatic 15 or 80 lines.
   - No type body above 400 lines.
   - No file above 600 lines.
   - Exceptions go in a short, reasoned list. Cohesive value-type files like `Models.swift`
     qualify only after a split was tried and rejected.
6. **Compile time**: no function body over 150 ms and no expression over 100 ms to type-check.
7. **Architecture invariants** (from AGENTS.md). Each grep must print nothing:
   ```bash
   grep -rlE '^(@testable )?import (GLTFCore|RendererRealityKit|RendererWebKit|RealityKit|WebKit)$' PreviewUI DesignSystem
   grep -rlE '^(@testable )?import (RendererRealityKit|RendererWebKit)$' GLTFInspector GLTFInspectorTests \
     | grep -vE '^GLTFInspector/(RealityKit|WebKit)/|^GLTFInspector/RendererRouter\.swift|^GLTFInspectorTests/(RealityKit|WebKit|CrossRenderer)/'
   grep -rnE '\b(Slider|Picker)\(|glassEffect\(|GlassEffectContainer|\bColor\(red:' PreviewUI
   ```
   As of today all three are clean. The third may need allowlisting for DesignSystem wrappers.
8. **Docs match code**: every backticked path in `AGENTS.md` and `docs/*.md` exists (a script
   that extracts the paths and runs `test -e`). Every type named there resolves with `grep`.
   There is no `TODO`/`FIXME` without a dex reference (4 today).
9. **Yield floor**: the last two waves each produced fewer than 3 accepted tasks, or less than
   0.5% net LOC change. Hard cap: 6 waves.

## 5. Pitfalls

- **Behaviour changes hiding in "pure" refactors (Swift)**:
  - SwiftUI view identity. Moving an `if` into a modifier, adding `AnyView`, or moving `@State`
    across an extracted view resets state.
  - `@Observable` invalidation scope changes when views are split.
  - Actor isolation and `Task` ordering when code moves across `@MainActor`.
  - Evaluation timing when `let` becomes a computed property, and `lazy`.
  - Struct↔class semantics.
  - Default-argument changes.
  - AGENTS.md pitfall #1: state touched in `View.init`.
- **Collapsing deliberate seams to shrink LOC**: the PreviewUI ↔ GLTFCore separation, the
  renderer silos (`#if canImport`) and `Engine*` adapters must stay. Put the invariant greps in
  every reviewer prompt.
- **Periphery deleting silo or DEBUG-only code**: it sees one configuration only. Before
  deleting near `#if`, grep the symbol across both branches, or scan again with
  `-- -configuration Release`.
- **Test-only code**: `--exclude-tests` results are not automatically dead. Some are test
  seams. Delete the code and its tests together, or keep both.
- **Goldens**: never regenerate them inside the loop. A pixel diff in a tidy PR is a bug.
- **Over-abstraction from dedupe**: merging clones that change for different reasons. Inline
  instead when unsure.
- **Reviewer inflation**: reviewers always find "something". Restrict them to behaviour and
  invariant violations.
- **Format churn**: no repo-wide reformatting. It blows up diffs and breaks parallel merges.
- **Parallel collisions**: separate worktrees and DerivedData or index stores per agent, and
  disjoint file sets per wave. `.dex` is root-only (see the memory note on worktree commit
  safety).
- **Tool trust**: Periphery is archived, and its Xcode 27 compatibility is unverified. If it
  fails, the fallback is a manual `grep`-based reference check per candidate, which is slow and
  not a replacement.

## Unresolved

- Periphery 3.8.0 against the Xcode 27 index store: one trial scan is needed.
- How Periphery reports `#Preview` macro expansions when `--retain-swift-ui-previews` is off.
  Expect preview-only views to show up. Confirm on the first scan.
- Whether `viewer.html` (project-authored glue, unlike the vendored bundle) is in tidy scope.
  If it is, jscpd and a manual review cover it, and none of the Swift tools do.
