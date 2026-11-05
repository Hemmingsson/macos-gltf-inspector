---
name: n-sol-loop
description: Trigger when the user says "sol loop", and before n-full-send asks for approval. One Sol reviewer, a few rounds, smallest fixes, on the local diff.
---

# n-sol-loop

One reviewer. It does not edit, commit, land, or start agents. You make the smallest change that answers a finding you agree with. Push back when the finding is wrong. Do not widen the diff to end the loop.

## Budget

- 3 rounds. Round 1 is the whole diff. Later rounds see the open findings and the code that changed.
- 5 rounds only while a blocker or should is still open with evidence, and the diff touches security, permissions, auth, data loss, or state and concurrency — or the user asks.
- Stop early when a round returns only nits. A declined nit, or a comment, doc, or format-only fix, needs no new round.

Keep `.atelier/tasks/<id>/sol.md`: id, severity, outcome (`fixed` / `disagree` / `declined`), and usage when the tool returns it. Never guess usage. Write `Sol: round N, <verdict>` on the task.

## Scope

`git status --short`. Do not stash, discard, or include unrelated files. When the change does not separate cleanly, stop and ask.

Base is `git merge-base HEAD main`. No `main`: a base the user names. Uncommitted work only: `HEAD`. One diff command for every round. State intent and out of scope in one or two sentences. Run the covering checks first (`n-verify`). Do not send a diff this change already breaks. Note a missing or already-red check in the brief.

## Start Sol

In T3: `orchestrator_capabilities`, then the latest Sol unless the user named one. `delegate_task` each round (`role: "review"`, `mode: "async"`). New `clientRequestId` per round. Save `taskId`. `childThreadId` is storage, not the next target. Do not use `t3_thread_send`, `create_threads`, or `t3_thread_launch`.

Outside T3: a native Sol subagent, same id across rounds. No Sol route: stop and say so. Do not substitute a model.

Do not edit the scoped files while it runs. Do not poll, and do not start a second reviewer. Timeout, error, or silence is not approval. On failure, cancel, confirm it stopped, and restart with the ledger.

Round 1 brief (no history):

```text
Review only. Do not edit, commit, land, or start subagents.
Repo: <abs path> Base: <sha> Intent: <intent> Out of scope: <scope> Checks: <results>
See: git diff <base> [-- <paths>]; git status --short (read untracked).
Read surrounding code. Find bugs, broken callers, mismatch with intent.
Skip style unless it hides a bug. Hold to the smallest change. Flag code, tests, or guards the intent does not need.
blocker = intended case wrong. should = real bug callers will hit, in intent. nit = rest.
Reply:
VERDICT: APPROVE or CHANGES
S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>
```

## Answer

Another path, a rare case, or a small cost is a nit, whatever label came back.

- Agree: smallest fix. Prefer a deletion or a narrower change over a new lock, cache, helper, or option. Fix the case that happened. When behaviour needs a test, add one focused test and watch it fail first (`n-tdd`).
- Disagree: one line, with file:line, a test, or command output.
- Out of scope or nit: decline in one line. Note a follow-up on the task when it is real work.

Re-run the covering checks. `git diff --shortstat` against the same base. When the review grew the diff, cut first.

## Next round

Start one only when budget remains and a blocker or should is open, behaviour changed, or the approval does not cover the current diff. Send the round 1 brief, the ledger, the same base diff, and the change since last round. Open ids and changed code only. Mark each old id `resolved` or `still open`.

## Stop

Agreed: `APPROVE` on the current diff, no open blocker or should, and no concern of your own. Stuck: the same item is still disputed after two replies, or the budget ends. Show both sides in two or three lines. The user decides. The budget ending is not approval.

Do not land during the loop.

Report: rounds, model, what changed, diff size before and after, fixed and declined findings with reasons, usage or "not exposed".
