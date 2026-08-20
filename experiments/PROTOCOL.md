# QuickPreview GLB Loading Optimization Protocol

Lead role: **performance orchestrator** for `quickpreview.app` (this repo: GLB Preview / Quick Look).

This is a controlled optimization campaign, not a normal coding task. Discover the smallest set of changes that produces the largest reproducible reduction in real GLB load time.

```text
baseline → evidence → research → hypothesis → isolated experiment (dex task)
  → sequential bench → verify → accept/reject → record in dex + ledger → next
```

Never:

```text
guess → change everything → one lucky run → declare victory
```

---

## Core objective

Reduce end-to-end GLB preview loading time.

Optimize for the user-visible path:

> User selects a GLB → Quick Look / host begins loading → the model is sufficiently rendered and usable.

Do not optimize an arbitrary internal timer unless it correlates with that metric.

**Primary metric (current harness):**

`total_load_ms = EntityLoader.load + StillRenderer.capture` (256² first still), aggregated as **sum of per-asset median `total_load_ms`** over the frozen 10-GLB corpus.

---

## Dex coordination (source of truth for work)

Use **dex** for persistent task coordination. Experiment IDs in git/docs stay human labels (`EXP-008`); **dex task IDs are local only** — never put them in commits, PRs, or public docs.

### Hierarchy

| Level | Dex type | Name pattern | Purpose |
|-------|----------|--------------|---------|
| L0 | Epic | `Optimization Experiments` | Whole campaign |
| L1 | Task | `EXP-NNN: short hypothesis` | One experiment = one task |
| L2 | Subtask (optional) | `Implement`, `Bench`, `Verify` | Only if a single EXP needs separable steps |

Do **not** create deeper trees. Do **not** invent empty EXP tasks ahead of evidence.

### Epic lifecycle

1. Create epic once (or resume if it exists):

```bash
dex create "Optimization Experiments" --description "$(cat <<'EOF'
## Goal
Reduce QuickPreview / Quick Look GLB end-to-end load time on the frozen corpus.

## Rules
- Follow `experiments/PROTOCOL.md`.
- One dex L1 task per experiment.
- Complete with KEEP or REJECT and evidence in `--result`.
- Never reference dex IDs in commits.

## Artifacts
- `experiments/corpus.json` (frozen)
- `experiments/baseline.json` (immutable)
- `experiments/results.json` + `WHAT-WE-TRIED.md`
- Final: `PERFORMANCE-OPTIMIZATION.md` when campaign stops
EOF
)"
```

2. For each approved experiment, create a child task under the epic:

```bash
dex create --parent <epic-id> "EXP-NNN: <one-line hypothesis>" \
  --description "$(cat <<'EOF'
## Classification
NEW | VARIANT (of EXP-XXX) | — duplicates forbidden

## Hypothesis
I believe X contributes Y to load time because Z.

## Parent champion
<label from results.json>

## Scope / forbidden
- …

## Research basis
- Links / docs / GitHub issues cited by research agent

## Approach
One meaningful change: …

## Done when
- Full 10-GLB bench vs same-machine champion control
- Correctness pass
- Decision KEEP | REJECT | INCONCLUSIVE recorded in `--result`
- `WHAT-WE-TRIED.md` + `results.json` updated
EOF
)"
```

3. Before any file edits for that experiment: `dex start <task-id>` (start the **child**, not only the epic).

4. When finished (accepted **or** discarded): `dex complete <task-id> --result "…"` immediately — do not batch.

### What goes in `dex complete --result`

Use Markdown. Required sections:

```markdown
## Decision
KEEP | REJECT | INCONCLUSIVE

## Hypothesis
…

## Change
files + one-sentence summary

## Champion control
sum_median_total_ms = …

## Candidate
sum_median_total_ms = …

## Delta
absolute ms, %, noise rule outcome

## Per-asset
notable wins/regressions (or attach path to `results/EXP-NNN.json`)

## Correctness
tests / proof / corpus load outcome

## Complexity
low|medium|high + why

## Reason
why keep/reject

## Must not retry
one line for WHAT-WE-TRIED
```

Use `--commit <sha>` when code landed on a keep branch; `--no-commit` for reject/research-only/docs.

### Parallel with files

| Artifact | Role |
|----------|------|
| Dex epic + EXP tasks | Work queue, status, handoff, completion evidence |
| `experiments/results.json` | Machine-readable champion chain |
| `WHAT-WE-TRIED.md` | Duplicate prevention (search **before** creating a dex EXP task) |
| `baseline.json` / `corpus.json` | Immutable campaign inputs |

Dex does **not** replace the ledger files; it owns **workflow state**. Ledger files own **reproducible history** in git.

---

## Subagents (orchestrator model)

You are the orchestrator. You do **not** sequentially guess optimizations yourself when specialists can isolate hypotheses.

### Hard rule: no parallel testing

- **May** run research / archaeology / hypothesis agents in parallel (read-only).
- **Must not** run two experiments’ benchmarks, builds, or correctness suites at the same time on the same machine.
- **Must not** let two agents mutate the same champion tree concurrently.
- Implementation agents use **isolated worktrees/branches**. Only the orchestrator promotes a KEEP into the champion.

Why: shared CPU/GPU thermal noise, disk cache pollution, and contested DerivedData make A/B deltas meaningless.

### Agent roles

| Role | Parallel OK? | Mutates champion? | Duty |
|------|--------------|-------------------|------|
| **Researcher** | Yes (read-only) | No | Web docs, Apple/RealityKit/Model I/O, glTF, GitHub issues/PRs, papers → candidate hypotheses |
| **Profiler** | With research | No | Where time actually goes on current champion |
| **Code archaeologist** | With research | No | Why code is structured this way |
| **Experiment implementer** | **One at a time** for build+bench | Only in own worktree | Protocol A–H below |
| **Regression verifier** | After implementer | No | Independent corpus/correctness check |
| **Complexity reviewer** | After implementer | No | Maintenance cost vs gain |
| **Performance reviewer** | Between rounds | No | Missed opportunities given profile |

### Round structure

```text
Round N
  1. Parallel (read-only): research + profile (+ archaeology if needed)
  2. Orchestrator: dedupe vs WHAT-WE-TRIED → create dex EXP tasks (priority order)
  3. Sequential: implementer A → full gate → complete dex task
  4. Sequential: implementer B → …
  5. Select next champion (if any KEEP)
  6. Update ledger + WHAT-WE-TRIED
```

Each implementer receives:

1. Current champion label + metric
2. Frozen corpus + bench command
3. Pointers to `WHAT-WE-TRIED.md` / `results.json`
4. Explicit forbidden/rejected approaches
5. **One** narrow optimization objective
6. Research citations that motivated the hypothesis

---

## External research (mandatory idea source)

Before proposing new experiments each round, spawn a **Researcher** that uses the internet — not only repo intuition.

### Sources to consult

- Apple docs: RealityKit, Model I/O, Quick Look, `Entity`, texture/material APIs relevant to this stack
- glTF / Khronos: extension specs (Draco, Meshopt, KTX2, etc.) and loader best practices
- GitHub: issues/PRs/discussions in related loaders, engines, and this repo’s history
- Performance write-ups: zero-copy buffers, decoder reuse, async texture upload, shader warmup — **only if applicable to native macOS path** (do not cargo-cult WebGL/Three.js tricks)

### Researcher output format

```text
Finding:
Relevance to our pipeline: high|medium|low
Hypothesis candidate:
Falsifiable claim:
Already tried? (cite WHAT-WE-TRIED)
Suggested EXP class: I/O | parse | decode | texture | scene | render | cache
Risk / complexity:
```

Orchestrator classifies each candidate:

| Class | Action |
|-------|--------|
| **NEW** | May create dex EXP task |
| **VARIANT** | Allowed only with explicit diff from prior EXP |
| **DUPLICATE** | Forbidden — do not create dex task |

Search `WHAT-WE-TRIED.md`, `results.json`, and git history **before** `dex create`.

---

## Corpus and baseline (immutable)

### Frozen 10-GLB set

- Source of truth: `experiments/corpus.json` (currently **v2**).
- Do not change the set because an optimization looks bad on it.
- Metadata per asset lives in `corpus.json` (size, meshes, materials, textures, extensions, roles).

### Baseline

- `experiments/baseline.json` is immutable for the campaign.
- Harness: `LABEL=<id> ./scripts/load-bench.sh`
- Minimum: **5** measurements per asset (more if noise is high).
- Prefer a **same-machine champion control** run when deciding KEEP.
- Noise rule (current): reject `|delta| < 3%` of champion sum unless same direction on ≥8/10 assets.

Unavailable stages must be marked unavailable — never invent `gpu_upload_ms` etc.

Commit baseline + corpus docs before optimization begins (already done for v2; re-baseline only if corpus version changes by explicit user decision).

---

## Size-ordered benchmarking (and early stop)

### Verdict on “bench small → large and stop early if no win”

**Using early stop as an acceptance gate is a bad idea.** Many real wins are **size- or content-dependent**:

- mmap / fewer copies → large files
- decoder/WASM reuse amortization → heavy Draco/Meshopt
- texture pipeline → many/large images
- animation/skin paths → skinned assets only

Stopping because tiny/small assets show ~0% would **miss** the campaign’s dominant cost centers (on v2: vegetation pack, mecha, animals, projector).

### Policy (required)

1. **Execution order:** always run assets **smallest → largest** (corpus order / ascending `bytes`). Rationale: fail fast on crashes, keep logs readable, thermal ramp is at least consistent.
2. **Smoke / abort early (allowed):** after the first few assets, abort the **candidate** run only if:
   - load/render **fails**, or
   - median regression vs control exceeds a hard abort threshold (e.g. **+15%** on ≥2 of the first 4 assets), or
   - obvious correctness break.
3. **Performance KEEP/REJECT:** requires the **full 10-asset** suite (or a documented hypothesis-scoped subset **plus** mandatory large-file controls — see below). Never KEEP from small files alone.
4. **Hypothesis-scoped subset (optional triage only):** if research claims “only helps files >50 MB”, you may **prototype** on the large tier first — but final decision still needs full corpus (to catch small-file regressions) and same-machine control.
5. **INCONCLUSIVE:** if full corpus delta is inside noise, do not merge; optionally increase reps rather than inventing a subset win.

```text
Size order = better orchestration
Early abort = only for broken/badly regressing candidates
Full corpus = only gate for KEEP
```

---

## Experiment implementer protocol (A–H)

Every optimization agent must:

### A. Inspect

Relevant pipeline only (do not modify production during pure investigation).

### B. Measure

Champion control on this machine before changing anything (or reuse a fresh control from this session if environment unchanged).

### C. Hypothesize

> I believe X contributes Y to load time because Z.

Falsifiable. Backed by profile and/or external research.

### D. Implement one meaningful change

One primary question. No bundled unrelated opts. Own worktree/branch.

### E. Benchmark

Full 10-GLB set, size-ordered, sequential. Same harness flags as champion.

### F. Verify correctness

Existing tests + all 10 load/render without meaningful visual/functional regression. No fidelity cheats.

### G. Complexity

Lines/files, abstractions, deps, concurrency, lifecycle, special cases. Prefer smaller robust wins over fragile larger ones.

### H. Report + dex complete

Return the standard experiment card; orchestrator updates `results.json` / `WHAT-WE-TRIED.md`; agent `dex complete`s the EXP task with the decision.

---

## Acceptance gate

KEEP only if **all** hold:

| Gate | Rule |
|------|------|
| Performance | Real reduction beyond noise; reproducible; not one lucky asset |
| Correctness | No meaningful regression |
| Complexity | Gain justifies complexity |
| Scope | On the Quick Look / preview load path |
| Honesty | No skip-required-work, no quality downgrade, no corpus special-casing |

REJECT (or INCONCLUSIVE) otherwise. Rejected experiments must not contaminate the champion branch.

Selection principle when multiple KEEps in a round:

> performance × confidence × simplicity

---

## Pipeline map (investigate, don’t edit blindly)

Trace file select → first usable frame. Note presence/absence of:

file I/O, copies, URLs, parse, glTF/GLB decode, Draco/Meshopt/KTX2, textures, materials, geometry, scene build, GPU upload, renderer/shader init, first render, post, thumbnails, cache, FS metadata, IPC.

Prioritize the next round from the **profile**, not from convenience. If textures are 37% and I/O is 8%, do not spend the round on I/O.

### Optimization classes (evidence-gated)

File access · loader init · GLB parse · decoding · textures · scene construction · rendering · caching (only if repeated work is measured).

### False optimizations (always reject)

Lower quality, skip textures/geometry, hide work past the metric boundary, incomplete “loaded”, disable features, special-case corpus, weaken tests, change the benchmark to flatter numbers.

---

## Champion chain

```text
experiments/
  PROTOCOL.md          ← this file
  README.md            ← short status pointer
  baseline.json        ← immutable
  corpus.json          ← frozen
  results.json         ← champion + experiment records
  WHAT-WE-TRIED.md     ← duplicate firewall
  results/EXP-*.json   ← raw runs
```

Every KEEP becomes the new champion parent. Never silently edit the champion. Rejected EXPs are not parents unless explicitly revisiting a VARIANT with a new falsifiable claim.

---

## Stop conditions

Stop when any holds:

- **Strong stop:** several consecutive rounds with no convincing KEEP
- **Practical stop:** remaining ideas need disproportionate complexity
- **Bottleneck exhaustion:** remaining time is unavoidable platform/GPU/library work
- **Target reached:** if a numeric target was set

Before stopping: full bench of original baseline vs final champion; write `PERFORMANCE-OPTIMIZATION.md` (executive result, corpus, before/after, history, what worked / didn’t, must-not-retry, remaining bottlenecks, complexity, reproduction).

Complete the dex epic with a summary result pointing at that document (`--no-commit` or release commit as appropriate).

---

## Git discipline

- Prefer `perf: …` commits for KEEps; one identifiable change per accepted experiment.
- Rejected work stays off the champion branch (worktree discard / revert).
- Do not squash away experiment history until the campaign ends.
- Never mention dex task IDs in commit messages.

---

## Orchestrator checklist (each round)

1. `dex list` / `dex list --ready` under Optimization Experiments
2. Search `WHAT-WE-TRIED.md` for duplicates
3. Parallel research + profile (no benches in parallel)
4. Create dex EXP tasks only for NEW/VARIANT
5. Run implementers **one after another** (worktrees OK; benches serial)
6. Acceptance gate → update champion or reject
7. `dex complete` each EXP with evidence
8. Update `results.json` + `WHAT-WE-TRIED.md`
9. Decide continue vs stop

Be skeptical. If it does not clearly win, reject it. If an agent has no evidence, send them to profile/research first.
