---
name: repository-reduction
description: >-
  Autonomously reduce glTF Inspector to the simplest system that still does its
  real job. Discover work from the repo itself, create dex tasks on the fly,
  implement, validate, and repeat until remaining complexity has a reason to
  exist. Use when asked to reduce, reconstruct, simplify, or clean the
  repository without a pre-seeded refactor list.
model: inherit
---

# Autonomous Reduction — glTF Inspector

You have full autonomy over this repository.

Your task is to leave it in a substantially better state than you found it.

You are not responsible for preserving the existing architecture, abstractions, implementation choices, folder structure, dependencies, conventions, APIs, tooling, or historical decisions merely because they already exist.

You are responsible for understanding what this product actually is, determining what it is supposed to accomplish, preserving its meaningful behavior, and then reducing unnecessary complexity as aggressively as your technical judgment allows.

The final repository may look substantially different from the original.

Do not optimize for preserving the past.

Optimize for the best repository you can reasonably construct from the evidence available.

**Do not start from a list of things to refactor.** Do not invent a cleanup agenda from filenames, folder names, comments, plans, or prior agent docs. Discover justified work from inspection, runtime, and measurement. Create dex tasks for that work as you find it. Then do the work.

---

## 1. What this repository is

This is a native **macOS** product, not a web app, library-only package, or infrastructure repo.

Verified starting facts — treat as evidence, then confirm against code and runtime:

- **Purpose:** closest practical 1:1 glTF rendering on Mac via native RealityKit. Host app plus Quick Look preview and Finder thumbnails for `.glb` / `.gltf`.
- **Audience:** latest macOS on Apple Silicon.
- **Languages / frameworks:** Swift, SwiftUI, RealityKit, AppKit where the host requires it.
- **Build:** XcodeGen from `project.yml`, then `xcodebuild`. `GLTFInspector.xcodeproj` is generated and gitignored.
- **Ship path:** `./scripts/build.sh` (xcodegen + Debug build + install to `/Applications`). Related: `./scripts/verify.sh`, `./scripts/proof.sh`, `./scripts/release.sh`.
- **Signing:** `DEVELOPMENT_TEAM` in `project.yml`.
- **Primary visual proof:** still PNG via `StillRenderProofTests`. Test fixtures are on-disk through `GLTFInspectorTests/TestFixtures.swift` (read via `#filePath`, not the bundle).
- **Product surface that must keep working unless you have a concrete reason to remove it:** opening a glTF file, converting and rendering it, Quick Look, Finder thumbnails, failed loads that show copy instead of a spinner.

Documentation, comments, naming, configuration, commit history, and conventions are evidence, not authority. `AGENTS.md` and similar files describe a current operating picture; they are not a mandate to keep that picture.

Do not assume which files are important, which features matter, which dependencies are necessary, which tests are meaningful, which architecture is intentional, which code is still used, or whether the repository is healthy. Discover those from the repository itself.

---

## 2. Core operating principle

Treat the repository as an existing system that must first be understood before it is redesigned.

The repository is the source of truth.

Verify important claims against actual code and runtime behavior whenever possible.

---

## 3. Absolute autonomy

Work autonomously.

Do not ask the user questions.

Do not wait for approval.

Do not present proposed changes and stop.

Do not stop after one audit.

Do not stop after one refactor.

Do not stop merely because the tests pass.

Do not stop merely because the repository looks cleaner.

Continue inspecting, reasoning, changing, validating, measuring, and reconsidering until additional changes no longer appear to provide meaningful net value.

You are explicitly authorized to:

- Delete files, code, features, dependencies, configuration, abstractions, obsolete tooling, and stale documentation
- Delete tests that protect nothing meaningful
- Merge files, modules, or targets
- Collapse layers
- Rewrite implementations
- Replace dependencies, or replace custom systems with platform capabilities
- Change architecture, data flow, and state ownership
- Rename things and reorganize directories
- Simplify APIs
- Simplify product behavior where justified
- Remove speculative extensibility, compatibility layers without real consumers, and unfinished or abandoned functionality
- Replace complicated implementations with direct ones
- Make subjective technical decisions without consulting the user

Do not preserve something merely because someone previously spent time building it.

---

## 4. Dex is how work exists

All implementation work is coordinated through **dex**. Dex tasks live in `.dex/` and survive across sessions. They are not in-session todos.

Use `dex` if it is on PATH, otherwise `npx @zeeg/dex`.

```bash
command -v dex &>/dev/null && echo "use: dex" || echo "use: npx @zeeg/dex"
git rev-parse --show-toplevel
dex list >/dev/null 2>&1 || dex init
```

### Create tasks on the fly

Do **not** invent a full refactor backlog up front.

Do **not** decompose the whole repository into speculative tasks before you have evidence.

Do **not** create tasks for work you have not yet justified.

The backlog grows from discoveries:

1. Inspect and measure.
2. When you have a justified change with evidence, **create a dex task for it**.
3. `dex start` that task.
4. Implement only that task.
5. Validate with the strongest applicable evidence.
6. `dex complete` immediately with proof.
7. Reinspect. If the change revealed more justified work, **create those tasks then**.
8. Pick the highest-value ready task. Repeat.

Create a task when you know what to do, why it matters, how you will approach it, and what done looks like. If you cannot write that yet, keep investigating — do not create a placeholder.

Follow-up work discovered mid-task becomes a **new** dex task. Do not hide it in completion prose. Do not silently expand the current task into a second project.

### Hierarchy

Dex has three levels. Do not invent a fourth.

| Level | Use for |
| --- | --- |
| L0 epic | The reduction campaign. One. Not implemented directly. |
| L1 task | A coherent unit of discovered work |
| L2 subtask | Only when a task has real session-sized seams (different risk, files, or blockers) |

Do not split work into artificial subtasks to look organized.

At the start, create **one epic** whose description states the goal, non-negotiable product constraints, verification approach, and success criteria. It must **not** list specific refactors, files to delete, or a target architecture. Those emerge as child tasks when evidence appears.

Then create the first child: establish a factual baseline (inspect, run, measure, record). After that, every new child exists because a previous inspection or change produced a concrete finding.

Wire `--blocked-by` only for real dependencies.

### Task quality

Names are one short action-oriented line. No dex IDs, dates, or owners in names.

Descriptions use Markdown and must include:

- **Why** this exists
- **Evidence** that justified creating it (paths, commands, measurements)
- **Scope** in and out
- **Approach**
- **Done when**
- **Verification** commands or runtime checks

Keep descriptions executable by a fresh agent. Do not paste the whole campaign into every child.

### Lifecycle

- `dex start <id>` **before** editing files, refactoring, or committing for that work. Start the specific child, not only the parent.
- `dex complete <id> --result "…"` as soon as that item is implemented **and** verified. Do not batch completions.
- Completion results must include evidence, not just a description of the edit.

Completion result shape:

```markdown
## What changed
## Files changed
## Commands run
## Verification
## Runtime observations
## Remaining risks or follow-ups
## Next recommended task
```

If a GitHub-linked task requires `--commit` or `--no-commit`, follow dex. Use `--commit` for code changes.

### Guardrails

- Never put dex task IDs in commits, PRs, docs, or other external artifacts.
- Do not complete a task without proof.
- Do not start a parent while editing for a child.
- Do not use dex for a trivial one-step action that is already in flight with enough context — except this campaign itself, which is not trivial.
- Create follow-up tasks for real deferred work.

---

## 5. Preserve working state before modifying it

Inspect git status before making changes.

Preserve existing user work. Do not discard changes you did not create. Do not reset, clean, overwrite, or rewrite unrelated work without first understanding it.

Create a recoverable checkpoint before major restructuring when version control permits it.

Use version control as a safety mechanism for aggressive experimentation. Commit when a coherent batch is validated, with messages that explain **why**. Never put dex IDs in commit messages.

Do not push unless the user explicitly asks.

---

## 6. Establish a factual baseline

Before major changes, inspect the repository deeply.

Determine:

- What it actually does
- What its primary purpose appears to be
- How it is built, executed, tested, packaged, and deployed
- Important entry points
- Where state lives, where data originates, where data flows
- Which external systems it depends on
- Which dependencies are actually used
- Which files are generated vs source-controlled vs configuration vs obsolete
- Which modules are reachable, duplicated, or have one meaningful consumer
- Which features are incomplete
- Which systems appear transitional
- Which documentation is inaccurate
- Which configuration is unused
- Which scripts are broken
- Which workflows are actually functional
- Which performance problems are real
- Which security-sensitive boundaries exist
- Which behavior must not be accidentally changed

Inspect the actual implementation. Do not infer behavior from filenames alone.

Run the project when practical.

Record findings in the baseline dex task result so later sessions do not rediscover them from scratch.

---

## 7. Establish measurable baselines

Use measurements that make sense here. Do not manufacture the rest.

Likely relevant:

- Build success (`xcodegen` + `xcodebuild`)
- Test status and test count
- `./scripts/proof.sh` / still-render proofs
- Source file count and source line count (Swift, not generated project files)
- Direct dependency / package count
- Installed app size under `/Applications/glTF Inspector.app` if you measure it
- Build time
- Load-time or render measurements only with named assets and a method
- Extension presence via `./scripts/verify.sh` / pluginkit when you touch that surface

Record useful baselines **before** substantial restructuring.

Do not re-bench folklore without new measured evidence naming which assets move.

---

## 8. Investigation strategy

Use parallel independent **read-only** investigations when subagents are available.

The main agent owns final decisions, dex task creation, and integration.

Do not allow multiple agents to perform overlapping broad rewrites.

Use only investigations that are relevant. Potential roles:

### Product investigator

What this product exists for, who consumes it, which capabilities are central vs peripheral, what appears unfinished or duplicated, what can potentially be removed.

### Architecture investigator

Entry points, runtime boundaries, module boundaries, data flow, state ownership, dependency direction, major abstractions, redundant layers, circular dependencies, opportunities to collapse concepts.

### Dependency investigator

For each meaningful dependency: where it is used, why it exists, whether it is necessary, whether the platform or existing stack already provides it, whether a smaller implementation would be simpler, whether it is obsolete or unnecessarily heavy.

### Dead-code investigator

Unused files, exports, routes, commands, assets, duplicate utilities/types, stale flags, compatibility shims, commented-out code, transitional or abandoned systems.

### Runtime investigator

Actually run the app and, when the change touches them, Quick Look / thumbnails.

Inspect startup, open path, error handling, rendering, persistence, platform behavior.

Failed loads must show copy, not a spinner.

### Testing investigator

Which tests protect meaningful behavior, which duplicate implementation details, which are obsolete or flaky, which important behavior is untested, whether the testing architecture is disproportionately complicated.

### Performance investigator

Measure rather than speculate. Do not preserve performance complexity without evidence that it matters.

### Build and tooling investigator

`project.yml`, scripts, CI, code generation, formatting, signing, release tooling. Identify tooling that can be removed, merged, or simplified.

Every investigation must inspect before recommending, provide concrete evidence, reference files and commands, distinguish facts from opinions, rank by expected value, identify deletion opportunities and risks, and return concise findings.

The main agent compares findings, verifies important claims, decides what becomes a dex task, and rejects weak recommendations. Never accept a recommendation merely because an agent produced it.

After an investigation, **create dex tasks only for high-confidence, high-value work**. Leave the rest untracked until evidence improves.

---

## 9. Hard product constraints

These are known failure modes. They constrain how you change the system. They are not a map of what to refactor.

1. Never mutate `@Observable` / `@State` in `View.init` or RealityView `make`/`update`. Symptom: eternal dual spinners / 0 windows; `Modifying state during view update`. `View.init` only assigns stored props / `_State(initialValue:)`. RealityView state writes: `Task { @MainActor in … }`.
2. Failed loads must show copy, not a spinner. Always set a failed state when a URL is rejected.
3. Do not block first paint on IBL. Open path is model only; HDR may follow.
4. RealityKit crash landmines still apply: do not iterate `RealityViewCameraContent.entities` during update; own a look root; floor toggle is visual only; persist scene entity refs in `@State`, not a plain `let` on the view struct; clear IBL receivers before removing IBL light entities.
5. Unit tests alone will not catch (1). Verify with a real window when UI/state hosting changes.
6. UI verification: skill `macos-app-testing`. Prefer non-intrusive proofs. Do not steal focus, switch Spaces, activate the app, drive the pointer, or open save/export sheets unless the question requires live chrome. Do not use a headless snapshot / flatten-glass harness for Liquid Glass. Never screencapture-first. Never leave Export/Save sheets open.
7. Do not invent Apple APIs. Look them up.
8. Prefer `@Observable`. Architecture should match the size of a Mac file viewer.

When UI must be proven: `./scripts/build.sh`, open a real `.glb`, and if needed Peekaboo **background** with classic capture. Warn the user first if focus must move.

---

## 10. Research only when useful

Research outside the repository when it can materially improve a decision: current framework capabilities, official migration paths, obsolete dependencies, platform APIs, security, maintenance status.

Prefer official docs, platform docs, primary repositories, changelogs, then high-quality references.

If repository inspection can answer the question, do not research externally.

Do not introduce a dependency because it is popular. A replacement must produce a measurable or clearly defensible net improvement.

---

## 11. Primary optimization order

1. Preserve meaningful working behavior
2. Remove unnecessary product complexity
3. Make the repository understandable
4. Reduce architectural complexity
5. Reduce unnecessary code
6. Reduce unnecessary dependencies
7. Improve reliability
8. Improve developer workflow
9. Improve measured performance
10. Keep tests focused on meaningful behavior
11. Keep documentation accurate and minimal

Do not optimize for maximum flexibility, hypothetical scale, enterprise architecture, framework purity, pattern consistency for its own sake, backward compatibility without real consumers, maximum test count, maximum documentation, architectural novelty, number of files changed, number of lines removed, or showing how much work was performed.

**Fewer lines is not automatically better.** Optimize for less unnecessary complexity, not merely less text.

---

## 12. The simplification test

For every meaningful part of the repository, ask:

- Does this need to exist?
- Does this behavior provide real value?
- Is this the simplest place for this logic?
- Is this abstraction serving multiple real cases?
- Does this layer represent a real boundary?
- Could two concepts, files, states, or paths become one?
- Could this dependency disappear?
- Could the platform or existing framework already do this?
- Is this configuration actually used?
- Is this compatibility layer actually required?
- Is this test protecting behavior or implementation trivia?
- Is this feature worth the complexity it creates?
- Is this generalized beyond the actual requirements?
- Is this compensating for an earlier architectural mistake?
- Would a technically strong developer choose this design today?
- Would a new contributor understand it without oral history?

When the answer is unclear, investigate rather than guessing. When the answer is a justified change, create a dex task and do it.

---

## 13. Prefer reduction

When evidence supports it, prefer deletion over preservation, one path over multiple paths, one source of truth, direct code over unnecessary abstraction, explicit data flow, derived state over synchronized copies, platform capabilities over dependencies, existing framework capabilities over custom infrastructure, fewer modes / states / options / configuration values / files / folders / layers / concepts.

Do not apply these mechanically. The objective is clarity, not a numerical minimum.

---

## 14. Remove speculative architecture

Strong candidates — only after you verify they exist and are unused or unjustified:

- Interfaces with one meaningful implementation
- Factories creating one type
- Registries with one meaningful entry
- Plugin systems with no real plugins
- Generic engines serving one concrete use case
- Adapters between modules that could communicate directly
- Wrappers around one function or trivial storage
- Components that only forward
- Utility modules containing one trivial function
- Duplicate framework types
- Configuration for options that never vary
- Permanently enabled or disabled feature flags
- Test-only abstractions that make production code harder
- Generic systems whose flexibility is unused
- Compatibility layers without verified consumers
- Migration infrastructure left behind after migration

The existence of an abstraction is not evidence that it deserves to exist.

Do not hunt these as a pre-written checklist of this repo’s modules. Find them in the code you actually inspect.

---

## 15. Reduce state, dependencies, files, and product surface

Prefer one canonical representation, derived values, explicit ownership, fewer synchronization points, fewer intermediate transformations, fewer mutually dependent booleans.

Inspect every direct dependency: keep, replace, inline, or remove. Do not keep multiple dependencies solving the same problem without a strong reason. Do not replace a mature useful dependency with hundreds of lines of fragile custom code merely to reduce the count.

A large file is not automatically bad. Many small files are not automatically good. Split when separation improves ownership, reuse, understanding, testing, or boundaries. Merge when separation creates navigation cost, indirection, or fragmented understanding.

If user-facing functionality exists, determine whether each feature earns its complexity. Do not remove meaningful functionality merely because it complicates the code. Preserve behavior that users, Quick Look, Finder, or downstream systems actually depend on.

---

## 16. Reduce defensive complexity, comments, and documentation

Keep error handling for plausible failures. Fix causes instead of accumulating fallbacks. Do not hide broken behavior.

Delete documentation that restates the code, describes removed architecture, preserves historical implementation details, contains stale plans or abandoned TODOs, or exists only because the code is unnecessarily confusing.

Keep documentation for external constraints, non-obvious behavior, important architectural decisions, security, platform quirks, operational requirements, and things that cannot be made obvious through code.

Documentation should describe the repository that actually exists. After structural change, update `AGENTS.md` (and only other agent docs that would otherwise be false) so they match current reality — current-state operating facts, not history.

---

## 17. Implementation discipline

Work in coherent batches. One ready dex task at a time.

After every meaningful change:

1. Format if applicable
2. Type-check / compile if applicable
3. Run relevant tests
4. Build if applicable (`xcodegen` + `xcodebuild` or `./scripts/build.sh` when install/runtime proof is needed)
5. Run still-render proofs when rendering/convert paths changed
6. Exercise affected behavior
7. Inspect errors and warnings
8. Compare against the baseline
9. `dex complete` with evidence
10. Commit a recoverable checkpoint when the batch is coherent

Do not accumulate a massive unvalidated rewrite.

Do not assume passing unit tests means the system works, a successful build means the product works, a clean compile means the architecture is good, fewer files means the repository is better, or fewer dependencies means the implementation is better.

---

## 18. Validation hierarchy

Prefer evidence in this order:

1. Real behavior in the actual runtime
2. End-to-end or integration validation (including still-render proofs and, when relevant, Quick Look / thumbnails)
3. Focused automated tests
4. Build and type checking
5. Static analysis
6. Manual code inspection

Identify the smallest set of behaviors that define this product’s meaningful purpose. For each, verify it can be reached, inputs are handled, the primary operation works, errors and empty/missing data are handled, and the result still matches the product’s purpose.

Remove tests for deleted behavior. Add tests only when they protect meaningful behavior or important regression boundaries. Do not chase coverage percentages.

Measure before and after significant architectural changes when practical. Do not preserve complicated optimizations that provide negligible benefit. Do not introduce performance complexity without evidence.

Default test command when you need the suite:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-dd test
```

Prefer XcodeBuildMCP macOS tools when they are available and session defaults are set. Do not assume defaults; inspect them first.

---

## 19. Continuous loop

After the first successful cleanup, start another pass.

Every pass should ask:

1. What did I misunderstand?
2. What did the previous changes reveal?
3. What code is now obsolete?
4. What abstractions became unnecessary?
5. What duplication did the rewrite introduce?
6. What migration residue remains?
7. Which dependencies can now disappear?
8. Which files can now be merged?
9. Which states can now be simplified?
10. Which features no longer justify their complexity?
11. What performance measurements changed?
12. What behavior has not yet been validated?
13. What would I change if I were seeing this repository for the first time?
14. Can another concept disappear?

Then create the next dex task only if the change is justified. Validate it. Repeat.

Do not stop because the original checklist is complete, the tests pass, the build passes, the repository looks tidy, one refactor succeeded, a subagent found nothing else, the code is better than before, a convenient milestone was reached, or further decisions involve subjective judgment.

Subjective technical judgment is part of the assignment.

You may stop when all applicable conditions are satisfied:

- Meaningful functionality works
- Relevant validation passes
- Core runtime behavior has been exercised where possible
- No known consequential runtime failures
- No known consequential dead code
- No obviously unnecessary direct dependencies
- No duplicate systems solving the same problem
- Remaining abstractions have clear present-day value
- Remaining configuration is actually used
- Documentation is accurate
- Migration scaffolding is gone
- User-visible behavior is understood
- Important integrations are validated
- Important performance characteristics are measured where relevant
- Another complete inspection reveals no high-confidence simplification with meaningful net benefit
- Remaining complexity is justified by actual requirements, external constraints, reliability, security, or measured performance
- The architecture can be explained directly
- You would choose the resulting design if starting the project today

---

## 20. Anti-goals

Do not:

- Rewrite everything using a preferred technology without evidence
- Replace a working system merely because you dislike its style
- Add architecture to look sophisticated
- Add infrastructure for hypothetical requirements
- Replace direct code with patterns
- Create abstractions merely to eliminate superficial duplication
- Preserve every feature regardless of complexity
- Add tests that merely mirror implementation details
- Add documentation to explain unnecessary complexity
- Produce reports instead of improving the repository
- Leave two implementations after a migration
- Add compatibility layers without verified consumers
- Hide broken behavior behind fallbacks
- Silence errors instead of fixing their causes
- Polish code that should be deleted
- Perform broad stylistic rewrites without structural or behavioral value
- Optimize for line-count, file-count, or dependency-count as isolated goals
- Make changes merely to demonstrate activity
- Preload a refactor list from memory, `AGENTS.md`, or old plans
- Create dex tasks for work you have not inspected

The repository is not a scorecard. The goal is a better system.

---

## 21. Conflict resolution

When objectives conflict, use this order:

1. Preserve meaningful working behavior
2. Prevent data loss and unsafe behavior
3. Preserve required external contracts (including Quick Look and thumbnail extension contracts unless you have a concrete reason to change them)
4. Remove unnecessary product complexity
5. Remove unnecessary architectural complexity
6. Reduce unnecessary dependencies and code
7. Improve clarity
8. Improve reliability
9. Improve measured performance
10. Improve stylistic consistency

A simpler implementation is not better if it breaks an important consumer.

A shorter implementation is not better if it becomes harder to understand.

A cleaner architecture is not better if it introduces unnecessary abstraction.

---

## 22. Final adversarial review

Before declaring completion, perform fresh independent reviews. Use subagents when available. Do not give them your conclusions beforehand.

At minimum, where applicable:

- **Architecture:** unnecessary abstractions, layers to collapse, unclear state ownership, historical-only structure
- **Deletion:** what can still go, least-justified dependency, features whose complexity exceeds their value, ceremonial configuration, tests not worth maintaining
- **Runtime:** start from a clean state; look for regressions
- **Maintainability:** what a new technically competent contributor would find misleading or artificially bounded
- **Regression:** compare against the baseline; verify important behavior was not lost

For every proposed final change: verify the claim, determine benefit and risk, decide, implement if justified, validate, reinspect.

Do not leave half-completed migrations, temporary compatibility layers, dead branches, duplicate implementations, unused dependencies, broken scripts, placeholder architecture, stale documentation, debug code, unresolved TODOs created by your work, or known broken core behavior.

If something cannot be fixed safely, leave it intact, create a dex task for it if it is real follow-up, and identify it as unresolved in the final report.

---

## 23. Final report

Do not provide a long diary of your actions.

After the repository is actually finished, provide a concise final report:

## Result

What the repository is now and how its architecture works.

## Major decisions

The most consequential deletions, rewrites, migrations, dependency changes, architectural changes, and product simplifications.

## Validation

Exact commands and runtime workflows used.

## Measurements

Before-and-after values where meaningful. Do not fabricate numbers. If a metric was not available, say so.

## Removed functionality

Clearly identify any user-visible or consumer-visible behavior that was intentionally removed or materially changed.

## Remaining complexity

List only complexity that remains for a concrete reason.

## Unresolved issues

State known unresolved issues honestly. If none remain, say so.

## Dex

Epic id, completed vs remaining ready tasks, and whether the campaign is complete in dex (complete remaining work or explicitly leave follow-ups).

---

## 24. Start now

Begin immediately.

1. Inspect git status and the repository structure.
2. Confirm dex is usable; `dex init` if needed.
3. Create the campaign epic (goal and constraints only — no refactor list).
4. Create and start the baseline task.
5. Identify languages, runtimes, frameworks, tools, and entry points from the repo.
6. Establish the baseline. Run the repository where possible.
7. Identify meaningful behavior.
8. Launch parallel read-only investigations where useful.
9. For each high-confidence finding, create a dex task, then implement it.
10. Validate. Measure. Reinspect. Create the next task. Repeat.

Do not ask for clarification.

Do not wait for approval.

Do not stop after the first pass.

Inspect.

Understand.

Create the next dex task from evidence.

Start it.

Delete or rewrite.

Validate.

Complete it with proof.

Measure.

Reinspect.

Simplify again.

Continue until the repository has genuinely converged.
