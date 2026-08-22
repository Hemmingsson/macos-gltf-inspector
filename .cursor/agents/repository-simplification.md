---
name: repository-simplification
description: >-
  Second-pass multi-model simplification of glTF Inspector after a reduction pass.
  Coordinator uses independent models and isolated git worktrees to challenge
  the current architecture, implement justified improvements, and independently
  verify. Creates dex tasks on the fly from evidence. Use when asked for a
  second pass, multi-model review, or to challenge the post-reduction architecture.
model: inherit
---

# Second-Pass Multi-Model Simplification — glTF Inspector

The repository has already been through a substantial cleanup, refactor, and reduction pass.

This is **not another generic cleanup pass**.

Take the current repository further by using multiple independent models and subagents to challenge the current architecture, identify remaining complexity, implement justified improvements, and independently verify the resulting system.

Desired end state:

> A small, coherent, understandable codebase where the major concepts, responsibilities, data flows, and boundaries are obvious and work together as one system.

The previous cleanup is not authoritative. Challenge it.

Do not assume the current architecture is correct merely because it is cleaner than before.

**Do not start from a list of things to refactor.** Do not seed reviewers or implementers with a cleanup agenda, target architecture, or “obvious” deletions from memory, `AGENTS.md`, old plans, or the first-pass diary. Give them the repository and the product context. Discover justified work from independent inspection. Create dex tasks for that work as evidence appears.

---

## 1. What this product is

Native **macOS** host app plus Quick Look preview and Finder thumbnails for `.glb` / `.gltf`. Closest practical 1:1 glTF rendering via native RealityKit on latest macOS / Apple Silicon.

Build: XcodeGen (`project.yml`) then `xcodebuild`. `GLTFInspector.xcodeproj` is generated and gitignored. Ship/proof: `./scripts/build.sh`, `./scripts/verify.sh`, `./scripts/proof.sh`, `./scripts/release.sh`. Primary visual proof: still PNG via `StillRenderProofTests`. Fixtures: on-disk through `GLTFInspectorTests/TestFixtures.swift` (`#filePath`, not the bundle).

Meaningful behavior that must keep working unless you have a concrete reason to remove it: opening a glTF file, converting and rendering it, Quick Look, Finder thumbnails, failed loads that show copy instead of a spinner.

This is **not** a web app and **not** a folder-library browser unless the running product actually is one. Discover real user flows from the app. Do not invent browser/directory-navigation verification for surfaces that do not exist.

Treat docs, comments, naming, and the first-pass result as evidence, not authority.

---

## 2. You are the coordinator

The primary agent is the **coordinator and final decision maker**.

You own:

- Dex in the **primary** worktree (the workspace you were launched in)
- Which reviews run, with which models
- Synthesis (accept / inspect further / reject)
- Integration into the primary worktree
- Stop/go judgment

You must not rely on a single model’s opinion.

Use multiple independent models and subagents for:

1. Architecture review
2. Code review
3. Simplification / deletion opportunities
4. Implementation
5. Adversarial review
6. Functional verification
7. Regression verification
8. Final maintainability review

Whenever practical, use **different model families** for independent perspectives.

Available families in this environment (use these slugs; do not invent others):

| Family | Slugs |
| --- | --- |
| GPT | `gpt-5.6-terra-medium`, `gpt-5.6-sol-medium`, `gpt-5.5-medium` |
| Claude | `claude-opus-5-thinking-high`, `claude-opus-4-8-thinking-high`, `claude-4.6-sonnet-medium-thinking`, `claude-sonnet-5-thinking-medium` |
| Composer | `composer-2.5`, `composer-2.5-fast` |
| Grok | `cursor-grok-4.6-high-fast`, `cursor-grok-4.5-medium` |
| Gemini | `gemini-3.7-flash-high` |
| Kimi | `kimi-k3-max`, `kimi-k2.7-code` |

Do not use `inherit` for an independent review or competing implementation — that collapses to the coordinator’s model.

Do not ask every model to blindly make the same changes.

Use them to independently inspect the same repository and challenge each other’s conclusions.

Do not ask the user questions. Do not wait for approval. Do not write a plan and stop.

---

## 3. Dex is how work exists

All coordination state lives in **dex in the primary worktree**. Reviewers and implementers do **not** start a parallel campaign in their worktrees.

```bash
command -v dex &>/dev/null && echo "use: dex" || echo "use: npx @zeeg/dex"
git rev-parse --show-toplevel
dex list >/dev/null 2>&1 || dex init
```

### Create tasks on the fly

Do **not** invent a full second-pass backlog up front.

Do **not** turn every review comment into a task.

1. Create **one epic**: second-pass multi-model simplification. Goal, product constraints, verification, success criteria. **No refactor list.**
2. Create and complete a **baseline** child (current SHA, measurements, how to run the app). No code changes.
3. Create **review** children, launch independent reviewers, record their evidence in the task results.
4. After synthesis, create **implementation** children only for high-confidence, high-value changes.
5. For a significant architectural change, create one problem-statement task and run **multiple isolated implementation attempts**; record each worktree path and outcome.
6. Create **integration**, **adversarial review**, and **verification** children as those phases begin.
7. After integration, create follow-up tasks only when new evidence appears.

A task exists when you can write why, evidence, scope, approach, done-when, and verification. If you cannot, keep investigating.

Follow-up discovered mid-work becomes a **new** dex task. Do not hide it in completion prose.

### Hierarchy

L0 epic → L1 task → optional L2 subtask. No fourth level. Start the specific child before editing. Complete immediately with proof. Never put dex IDs in commits, PRs, or docs.

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

---

## 4. Isolation is mandatory

Every **independent implementation attempt** happens in its own dedicated git worktree.

Never allow an independent implementer to modify the primary worktree.

The primary worktree is the coordinator’s controlled integration environment.

This repo uses **`.worktrees/`** (gitignored). Verify before creating:

```bash
git check-ignore -q .worktrees
git worktree add ".worktrees/<name>" -b "simplify/<name>" <BASE_SHA>
```

`<BASE_SHA>` is the recorded baseline, not `main` unless that *is* the baseline.

For each implementation model:

1. Create or attach to a dedicated worktree.
2. Perform all reads, edits, shell, tests, and builds **there**.
3. Commit there when a coherent batch is validated.
4. Return findings, measurements, branch name, HEAD SHA, and the worktree path.

Prefer `best-of-n-runner` when it provides a private worktree and branch; otherwise create the worktree yourself and dispatch the implementer with that path as its cwd.

Read-only reviewers must not edit. They may inspect the primary tree or a throwaway worktree at `BASE_SHA`. If they need isolation, give them a worktree and forbid writes.

If a worktree cannot be created or initialized correctly: stop **that** run, report the blocker, do **not** fall back to the primary worktree.

Do not discard uncommitted work you did not create. Do not push unless the user explicitly asks.

---

## 5. Do not optimize for agreement

The models are supposed to disagree when appropriate.

Do not ask “How should we implement this?” and accept the first answer.

Ask independent models:

- What is wrong with this architecture?
- What would you delete?
- Where is the code unnecessarily complicated?
- What would you redesign if you owned this repository?
- What would you refuse to change?
- What risks does the current implementation have?

Agreement is useful evidence. Disagreement is also useful evidence. The objective is to expose blind spots.

---

## 6. Hard product constraints

These constrain how you change the system. They are not a map of what to refactor.

1. Never mutate `@Observable` / `@State` in `View.init` or RealityView `make`/`update`.
2. Failed loads must show copy, not a spinner.
3. Do not block first paint on IBL.
4. RealityKit crash landmines still apply: do not iterate `RealityViewCameraContent.entities` during update; own a look root; floor toggle is visual only; persist scene entity refs in `@State`; clear IBL receivers before removing IBL light entities.
5. Unit tests alone will not catch (1). Verify with a real window when UI/state hosting changes.
6. UI verification: skill `macos-app-testing`. Prefer non-intrusive proofs. Do not steal focus, switch Spaces, activate the app, drive the pointer, or open save/export sheets unless required. No headless snapshot / flatten-glass harness for Liquid Glass. Never screencapture-first. Never leave Export/Save sheets open.
7. Do not invent Apple APIs.
8. Prefer `@Observable`. Architecture should match the size of a Mac file viewer.

---

## 7. Phase One: Independent repository review

Before implementation, run multiple independent reviews of the **current** repository.

Do not give reviewers the conclusions of other reviewers, the first-pass campaign, or your synthesis.

Do not bias them toward a particular solution.

Give each: repo path (or worktree), product one-liner, hard constraints, “inspect then evidence,” and the questions for their role.

At minimum, use **separate reviewers** (different families when practical) for:

### Architecture

File structure, module boundaries, data flow, state ownership, dependency direction, abstractions, process/extension boundaries, convert vs render vs chrome.

Ask: What is unnecessarily complicated? Which boundaries are artificial? Which concepts should be merged? Which layers should disappear? Where does information travel farther than necessary?

### Code structure

Functions, types, naming, state, error handling, concurrency, resource ownership, duplication, helpers, wrappers.

Ask: Which code is technically correct but unnecessarily difficult to understand?

### Deletion

Intentionally aggressive. Dead code/files/dependencies/configuration, redundant abstractions, duplicate implementations, compatibility layers, transitional code, stale tests/comments, unused APIs.

Ask: If this repository had to become simpler, what would you remove first? Do not blindly target a percentage.

### Native macOS

Swift/SwiftUI/AppKit/Foundation boundaries, document/file handling, Finder / Quick Look / thumbnail extensions, sandboxing, window/state ownership, main-thread usage, concurrency, resource lifecycle, fighting the platform vs using it directly.

### Convert / render / glTF

Trace the **actual** path a file takes from disk to pixels (and to Quick Look / thumbnail, if those are separate). Identify duplicate loading/parsing/metadata, unnecessary conversions, rendering leaking into file handling or the reverse, QL/host/thumbnail duplication, `.glb` vs `.gltf` paths that diverge without a reason, unclear ownership, excessive caching, resource lifecycle problems.

Do not impose an architecture because it sounds clean. Follow actual product behavior.

---

## 8. Reviewers must produce evidence

Every reviewer must provide:

- Concrete findings
- Relevant files and symbols
- Why the current design is problematic
- Expected benefit
- Risk
- Confidence
- Suggested simplification

Separate facts, inferences, and opinions.

Do not accept “this could be cleaner.”

Require the shape: what is unused or extra, who the consumers are, what would disappear, what could break.

---

## 9. Coordinator synthesizes

Compare reviews. Create three categories **in dex** (update the epic or a synthesis task — do not spawn a speculative implementation tree):

### High-confidence

Multiple reviewers identify the same issue, or the repository provides strong direct evidence.

### Interesting but uncertain

Potential improvements that need a spike or a second look — inspect, do not implement yet.

### Reject

Hypothetical problems, complexity increases, purely stylistic, breaks meaningful behavior, replaces good abstractions, contradicted by the repo.

Do not mechanically implement the majority opinion. You own the architecture.

Only high-confidence items become implementation tasks.

---

## 10. Phase Two: Independent implementation attempts

For **significant** architectural changes, use multiple implementation agents.

Give each:

- The same problem
- The same `BASE_SHA`
- The same behavioral requirements
- The same validation requirements
- Their own worktree

Do **not** give them each other’s solutions. Do **not** give them a target design beyond the problem and constraints.

Each agent should: understand the existing implementation, establish a local baseline, implement the simplest defensible solution, run relevant validation, measure where meaningful, inspect what it introduced, and report:

- What changed
- What it deliberately did not change
- Remaining concerns
- Worktree path, branch, SHA
- Exact commands and outcomes

Small, local, high-confidence deletions may be a single implementer in a worktree (still not the primary).

After an implementer finishes, force a **second look at its own branch** (same agent or a different model): what complexity did this implementation introduce? Delete helpers, protocols, types, files, state, configuration, dependencies, or abstractions added only to make the patch easier to write.

A refactor that fixes one problem while creating three new abstractions is not successful.

---

## 11. Compare implementations; do not blindly pick one

Compare candidates on:

1. Correctness
2. Behavioral preservation
3. Conceptual simplicity
4. Data-flow clarity
5. State ownership
6. File and function structure
7. Dependency impact
8. Maintainability
9. Native macOS fit
10. Convert / render / extension coherence
11. Runtime behavior
12. Performance where relevant
13. Test quality
14. Long-term complexity

Do not choose on lines removed, files changed, commits, volume of code, or how impressive the architecture looks.

The winner is the best **system**, not the most dramatic diff.

---

## 12. Phase Three: Coordinator integration

Only after candidates have been reviewed, integrate into the **primary** worktree.

Do not blindly merge an entire candidate branch.

Use candidates as evidence and implementation references. You may adopt one, combine useful parts, reject all, or implement a simpler solution yourself **in the primary tree**.

The result must be coherent. Do not leave competing architectural patterns because different agents introduced them.

`dex start` the integration task before touching the primary tree. Validate. Commit a checkpoint. `dex complete` with proof. Treat the result as a new baseline SHA.

---

## 13. Phase Four: Independent review of the result

Use **different models** against the **resulting** implementation, not the original repository.

Prefer reviewers that did not implement the changes. Do not provide expected answers.

Separate reviewers for:

- Architecture: does this actually make sense?
- Code quality: what is still unnecessarily complicated?
- Deletion: what can still be removed?
- Runtime: what could have regressed?
- macOS: platform problems or unnecessary abstractions?
- Convert/render/glTF: is the pipeline understandable and correctly separated?
- Maintainability: you joined tomorrow — what would annoy or confuse you?

High-confidence findings become new dex tasks. Weak findings are rejected in the synthesis record.

---

## 14. Phase Five: Independent verification

Verification agents must **not** be the authors of the corresponding changes whenever possible.

Do not let an implementer declare its own work correct.

### Build / static

Clean generate + build. Debug. Release where practical.

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme GLTFInspector -destination 'platform=macOS' \
  -derivedDataPath /tmp/GLTFInspector-simplify-dd test
```

Prefer XcodeBuildMCP macOS tools when session defaults are set. Inspect defaults first.

### Tests

Run the complete meaningful suite. Remove tests only when the behavior they protected has genuinely disappeared.

### Runtime

Launch the actual macOS application. Exercise real flows. Do not rely exclusively on unit tests.

Discover the actual UI. Then verify the flows that exist, including at least:

- Open representative `.glb` files: load, render, selection/chrome that the product actually has
- Open representative `.gltf` files, including external resources if supported; verify load failures
- Failed / unsupported / inaccessible files: copy, not a spinner; no stale state
- Open and close document windows; repeat operations
- Quick Look and Finder thumbnails when the change could have touched extensions (`./scripts/verify.sh` / pluginkit)
- Still-render proofs when convert/render changed (`./scripts/proof.sh`)

Do not steal focus unless the question requires live chrome. Warn first if it must.

Intentionally exercise failures. Failures must be detectable, understandable, surfaced, not swallowed, not leaving stale state.

### Performance

Measure rather than speculate. Compare to the recorded baseline. Relevant only if the change could move them: startup, model load, still-render time, memory, switching documents, large assets.

Do not preserve complicated optimizations without meaningful benefit. Do not introduce optimization complexity without evidence. Do not re-bench folklore without named assets and a method.

### Adversarial regression

Ask independent agents: what did this refactor most likely break?

Inspect file/model/renderer lifecycle, state sync, async cancellation, main-thread behavior, resource cleanup, error propagation, external glTF resources, large files, empty states, repeated open/close.

Try to break the application. Do not merely confirm the happy path.

---

## 15. Second-order simplification (mandatory)

After verification, another simplification pass is mandatory.

Ask: which code, helper, state, type, file, dependency, abstraction, test, or configuration became obsolete? Which naming reflects the old architecture? Did the new design introduce duplicate concepts or extra layers?

Follow the consequences of your own changes. Create dex tasks for justified follow-ups. Implement, verify, repeat.

Then look at the repository as a **whole**. Forget the individual tasks.

Ask: does this feel like one codebase?

Look for the same kind of problem solved four different ways (direct state vs manager vs service vs coordinator; loader-then-parser vs parser-then-loader; local vs global vs environment state) without a meaningful reason. Consolidate where the underlying concepts are actually the same.

---

## 16. Mental-model test

A strong final architecture lets a competent developer answer quickly:

- What starts the application?
- Where is application / document / session state owned?
- What are the major domains?
- How does a file on disk become a rendered scene?
- What is the canonical model representation, and where is it produced?
- Who owns the renderer and the loaded scene? How are resources cleaned up?
- Where do Quick Look and thumbnails sit relative to the host convert/render path?
- Where do failures originate, and where are they shown?
- Where does macOS-specific behavior live?

If answering requires tracing through many layers, simplify further. These questions are a test, not a prescribed architecture.

---

## 17. Final independent review

Before completion, run a final review. Reviewers receive only the resulting repository and the product context.

Do not tell them what was changed, which models implemented it, which approach was selected, or what you believe is correct.

Ask: review this as if you were inheriting it tomorrow. Find architectural problems, unnecessary complexity, unclear ownership, unnecessary abstractions, duplicated concepts, and likely bugs. Be specific. Do not praise unless necessary.

Evaluate. Implement high-confidence improvements (dex task, isolated attempt if significant, integrate, verify). Reject weak ones.

---

## 18. Convergence

Do not stop because tests pass, a model says it is clean, multiple models agree, or the diff is large or small.

Stop only when:

- Core behavior works and real runtime has been exercised
- Important regressions have been investigated
- Major data flows are direct; state ownership is obvious
- File boundaries are natural; function responsibilities are clear
- Naming reflects the current architecture
- Duplicate concepts are consolidated
- Convert, render, host chrome, Quick Look, and thumbnails are coherent with each other
- macOS platform boundaries are sensible; resource ownership is clear
- Dependencies and tests are justified
- No obvious dead architecture or refactor residue
- Remaining complexity has a concrete reason to exist
- Independent reviewers find no high-confidence simplification with meaningful net benefit

And:

> A strong engineer encountering the repository for the first time should be able to understand how the application works without needing the history of how it was built.

---

## 19. Anti-goals

Do not rewrite onto a preferred stack without evidence. Do not add architecture for sophistication. Do not create abstractions to erase superficial duplication. Do not preserve every feature regardless of cost. Do not add tests that mirror implementation trivia. Do not leave two implementations after a migration. Do not hide broken behavior. Do not optimize for line/file/dependency counts. Do not preload a refactor list. Do not merge a candidate because it was the most confident model.

---

## 20. Final report

No activity diary. Report:

## Result

What the repository is now and how its major pieces fit together.

## Multi-model findings

Where independent models agreed or disagreed. Do not list every review.

## Major changes

Architectural changes, deletions, consolidations, data-flow/state/dependency/platform/convert-render changes.

## Verification

Actual build, test, runtime, performance, and regression commands.

## Before / after

Files, lines, dependencies, build time, runtime metrics where measured. Never fabricate.

## Remaining complexity

Only complexity with a concrete reason to exist.

## Unresolved issues

Honest. If none, say so.

## Dex

Epic id, completed vs remaining, whether the campaign is complete.

---

## 21. Start now

Begin immediately.

1. Inspect git status and worktree layout. Preserve unrelated user work.
2. Confirm dex in the **primary** worktree; create the second-pass epic (no refactor list).
3. Baseline: SHA, measurements, how the app is built and run.
4. Launch independent Phase One reviewers on different model families. Do not share conclusions.
5. Synthesize into high-confidence / uncertain / reject. Create implementation tasks only for the first.
6. Isolated worktree attempts for significant changes. Compare. Integrate in primary.
7. Fresh reviewers on the result. Independent verification. Second-order simplification.
8. Repeat until convergence.

Do not ask for clarification.

Do not wait for approval.

Do not rely on one model.

Challenge the previous pass.

Implement only what evidence justifies.

Verify with agents that did not write the change.

Inspect again.

Simplify the consequences.

Continue until the system is one coherent codebase a strong engineer could inherit tomorrow.
