---
name: n-full-send
description: Trigger when the user says "full send", or when a reviewed worktree is ready to land. Proves the change, gets a Sol review, launches the app for approval, then fast-forwards main and completes the task.
---

# n-full-send

The user is not watching this thread. Stay with it until `main` holds the change, or you have asked with the question tool and stopped. "Full send" is permission to run the checks below and, after the user approves the running app, to land on `main`.

That permission covers the project's tests, the app, screenshots, and the other checks proof needs, even when a note says to ask first. Use the command, fixture, and check the project names. It does not cover deleting data, production, or anything outside the repo. A harness approval prompt still applies.

1. **Finish.** The task is in progress. The change is the smallest one that meets it. No open Critical or Important finding.
2. **Prove** (`n-verify`). Every change in the diff has evidence from this session: a test that went red then green, or the app showing the behaviour. When there was a failure, reproduce it, apply the fix, and watch the same check pass. Run the project's suite. A green mock does not prove a screen. You cannot prove a change: ask, and do not land.
3. **Sol.** `n-sol-loop` on this diff, unless `.atelier/tasks/<id>/sol.md` already records `APPROVE` for this HEAD.
4. **Launch.** The project's run command (`AGENTS.md`), from the task's worktree when it has one, otherwise the current checkout. Use the screen or fixture that shows this task. Send `n-visualizer` (background) for the `after` capture, same framing as `before`, or a diagram when it is not visible. Wait for the picture.
5. **Ask** with the harness question tool (`AskUserQuestion` in Claude Code, `request_user_input` in Codex), so the session shows it is waiting. Include what changed, what is on screen, the proof, the Sol outcome, and your rulings. Options: *Approve and land* · *Change something*.
6. **Land** on approval. A worktree lands with `n-worktrees`. Already on `main`: there is nothing to fast-forward. A rebase that changes behaviour: stop and ask. Then run the suite on `main` (`n-verify`).
7. **Complete.** `backlog complete <id> --commit <sha> --result "…"`. Open with the picture (`![before]` / `![after]`, the live demo, or the diagram), then the test evidence, then what changed, then each decision you made. Commit the `.atelier/` changes with the work.

**Done when** `main` holds the change, the suite is green on `main`, the worktree is gone, and the task is complete with proof.

No question tool, or no answer: do not land. Start the final message with the question.

Ask only when you cannot prove the change, you cannot land it, the next step deletes data or leaves the repo, or the goal is ambiguous in a way that changes the result. "Change something" returns to the task. It stays in progress. Decide everything else and list it in the result.
