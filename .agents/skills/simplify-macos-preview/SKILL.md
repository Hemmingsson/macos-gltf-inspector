---
name: simplify-macos-preview
description: >-
  Organic deep-simplification loop for glTF Inspector (macOS .glb/.gltf preview).
  Identifies one cut at a time; researches it; implements immediately via cheap fast
  workers; tracks each cut as a dex task; completes only after verification; escalates
  to stronger models when tests fail. Use when simplifying the repo, cleaning post-
  WebKit/Filament→Metal architecture, or running a simplification worktree loop.
disable-model-invocation: true
---

# Simplify macOS glTF preview

You clean **implementation**, not product intent. Features are roughly right; the code is
bloated and shaped by dead history (WebKit page, Filament spike, extra UI frameworks).
Goal: a senior macOS engineer could defend every file as a **simple, fast, accurate
preview + light inspection** app — nothing else.

**Explore and define.** Do not inherit a fixed architecture from this skill. Discover what
the app actually is from code + running app, then make the repo match that understanding.
Prefer subtraction. Prefer finishing one cut over planning a batch of ten.

## Orchestration & models

You are the **orchestrator**: look, suspect, decide the cut, write the dex ticket, review
diffs, escalate, complete. Do **not** burn the parent model on bulk edits or long test logs.

Canonical routing: personal skill `fast-delegation` (Composer 2.5 fast → Grok → Claude).

| Step | Who | Model |
| --- | --- | --- |
| Look / suspect / research the cut | parent (or `explore` for volume search) | parent / `composer-2.5-fast` |
| Implement a **fully specified** cut | `fast-worker` (`implement`) | `composer-2.5-fast` |
| Run `dev.sh test` / pixel gate / scrape logs | `fast-worker` (`verify`) | `composer-2.5-fast` |
| Cut needs diagnosis or spans modules | `task-implementer` | `grok-4.7-medium-fast` |
| Same cut failed verify twice, or `NEEDS_CONTEXT` | escalate one ladder step | see `fast-delegation` |
| Keep/reject architecture, merge judgment | parent | user's picker |

**Implement → verify fast.** After `dex start`, hand the worker: exact files, the change,
what not to touch, and the verify commands. Parent reads the return; if green →
`dex complete`. If red → escalate with failure evidence (command, failing tests, short
diff hunks) — do not re-prompt the same cheap model blindly a third time.

Keep tiny one-file edits on the parent when a subagent would cost more than the edit.

## Setup (once)

1. Inspect `git status` in the primary checkout. Do not touch unrelated dirty work.
2. Create a dedicated branch + worktree (unless the user already gave you one):

```bash
git fetch origin
git worktree add -b refactor/simplify .worktrees/simplify origin/main
cd .worktrees/simplify
```

3. Baseline: `./scripts/dev.sh test`. Note existing failures separately from new ones.
4. Optional parent epic: `dex create "Simplify preview app" -d "…"`. Each cut is a child
   (`--parent <epic-id>`) or a standalone L1 if there is no epic.
5. Keep a living sketch in `.agents/handoffs/YYYY-MM-DD-simplification.md` (a few sentences
   on modules + data flow). Update it when your model of the app changes — it is not a plan
   to execute blindly.

Repo facts and verify commands: [references/repo.md](references/repo.md).

## Organic loop (repeat until done)

**One cut at a time. No implementation batches.**

```text
look → suspect → research → task → implement → verify → complete → look again
```

### 1. Look

Re-read the tree with fresh eyes. Trace real paths (file open → pixels + sidebar; Quick Look;
thumbnail; Settings → extensions; failed load). Hunt leftovers: old names, second sources of
truth, wrappers with one caller, dead targets, docs that lie.

### 2. Suspect one thing

Pick the **highest-leverage** next cut you can defend (delete a layer, merge two owners,
rename a concept, collapse duplicate state). Write it as one sentence. If you cannot name
the win, keep looking — do not invent work.

### 3. Research (assumptions must be correct)

Before editing, prove:

- What still calls it / depends on it (incl. extensions, tests, scripts, App Group keys).
- Whether removing or changing it alters user-visible behavior or Khronos pixel parity.
- The simpler replacement (often: delete, or inline into the real owner).

If research shows the suspicion was wrong, drop it and look again. Do not “simplify” into a
worse shape.

### 4. Record the task, then start it

```bash
dex create "Short cut name" --parent <epic-id> -d "$(cat <<'EOF'
## Why
<one or two sentences>

## Scope
- …

## Done when
- Code matches the cut
- ./scripts/dev.sh test green (or known failures unchanged)
- <pixel gate / run fixture if render or UI touched>

## Out of scope
- …
EOF
)"
dex start <id>
```

Ticket shape follows project norms (Why / Scope / Done when). Keep it tight — this is a
work order for **this cut**, not a roadmap.

### 5. Implement immediately (cheap/fast)

Dispatch a **fully specified** cut to `fast-worker` + `composer-2.5-fast` (or
`task-implementer` if diagnosis is required). Finish the migration in one pass (no parallel
old/new, no shims “for later”). Worker prompt must include scope, decisions already made,
and verify commands.

Judgement for the orchestrator (not a checklist to force):

- Prefer deletion → rearrange → new structure.
- Prefer direct code over protocols/adapters unless a hard boundary needs them (e.g. app
  extension, sandbox).
- One concept, one name, one owner.
- UI stays separated from render guts; chrome talks to a small public canvas/API surface.
- Failed loads stay `.failed(message)`, never a spinner.

### 6. Verify fast, escalate if red, then complete

Run what the ticket promised via `fast-worker` (`verify`) when logs are long (at least
`./scripts/dev.sh test`; pixel gate / `./scripts/dev.sh run <fixture>` when render/UI
changed — see [references/repo.md](references/repo.md)).

- **Green** → `dex complete <id> --result "…" --no-commit` (or `--commit <sha>`).
- **Red** → orchestrator diagnoses briefly; escalate one ladder step with failing command +
  relevant hunks; re-verify; only then complete. Never weaken tests to go green.

Commit coherent cuts on the simplify branch when it helps recovery (`why` in the message).

### 7. Look again

Immediately search for the **next** cut. The loop is the product of this skill — not a
batch of tickets filed for later.

## Stop when

A full re-read finds nothing you would still remove, merge, or rename, and you can explain
the architecture in a few sentences. Then report:

1. Architecture (few sentences)
2. Cuts made (and dex ids)
3. Removed complexity
4. How a file becomes pixels + panel content
5. Verification + before/after metrics if meaningful
6. Leftovers / risks

## Guardrails

- Preserve intended product behavior; challenge implementation.
- Do not discard unrelated dirty work in other checkouts.
- Do not force-push `main` / rewrite published history unless the user asks.
- Do not invent a second renderer, a settings path outside the App Group, or silent
  compatibility shims for pre-v1 names unless the user asks for stability.
- Prefer platform + existing repo tools (`dev.sh`, dex/backlog, XcodeGen) over new machinery.
