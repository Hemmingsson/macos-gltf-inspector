# .fejk-agents — next-workflow (draft)

Spec-driven and test-first. Skills are prefixed `n-` so they do not collide with the live `m-` plugin at `~/.agents/plugins/m-workflow`.

| Read | For |
| --- | --- |
| [CHANGES.md](CHANGES.md) | Draft log. Not instructions. |
| [WORKFLOW.md](WORKFLOW.md) | How it runs: where to enter, one task start to land, an epic over time. |
| [GLOSSARY.md](GLOSSARY.md) | The words the skills think with: epic / task / subtask (L0–L2), red, green, land, … |

## Layout

```text
.claude-plugin/plugin.json      plugin "next-workflow"
hooks/
  session-start                 injects using-next-workflow in full; adds the board after compact/resume/clear
  task-guard                    blocks code edits while no task is in progress (repos with a backlog board only)
skills/
  using-next-workflow/          router + board rules + three laws (injected, not model-invoked)
  n-backlog/                    backlog CLI/MCP, rich L0–L2 formats, .atelier artifact paths, visuals
  n-brainstorm/                 why → grilling rounds → approaches → spec on the L0 epic → approval; visual companion
  n-breakdown/                  epic spec or existing plan → tasks (L1), subtasks (L2)
  n-tdd/                        red → green → refactor; bug branch
  n-worktrees/                  detached .worktrees/<id>; land onto main
  n-parallel/                   independent tasks or failures, one message
  n-execute/                    this session, one task at a time
  n-subagents/                  one n-implementer per task, then a task review
  n-build/                      picks n-execute or n-subagents
  n-verify/                     fresh command output before a pass, fixed, or done claim
  n-review/                     n-task-reviewer or n-code-reviewer, then act
  n-sol-loop/                   one Sol reviewer on the local diff
  n-full-send/                  prove → Sol → launch → approve → land → complete
agents/                         n-implementer, n-task-reviewer, n-spec-reviewer, n-code-reviewer, n-visualizer (background)
scripts/sync-agents.py          one Markdown source → Cursor + Claude (symlinks) and Codex (TOML)
tests/                          one scenario per behaviour; bash tests/run.sh runs them all on Codex
diagrams/                       SeeCode specs (.json), interactive (.html), images (.png)
```

Still the live plugin, not redrafted here: `m-research`, `m-explainer`, `m-simplify-code`, and the `researcher` agent. The board skill is `n-backlog`.

Cursor and Codex load these skills through symlinks in `.agents/skills/` (`.cursor/skills` points there).

## Agents in Claude, Cursor and Codex

Agent files hold the role, the boundary, and the reply, and point at the skill that holds the procedure. One Markdown source serves all three tools:

```bash
python3 .fejk-agents/scripts/sync-agents.py --src .fejk-agents/agents --cursor .agents/agents --codex .codex/agents   # this repo
python3 .fejk-agents/scripts/sync-agents.py --src ~/.agents/agents --codex ~/.codex/agents                         # global
```

Cursor and Claude get symlinks; Codex gets generated TOML. Edit the `.md`, then re-run.

## Try it

```bash
claude --plugin-dir .fejk-agents
```

Disable the live `m-workflow` plugin for that session so the two bootstraps don't compete.

## Test a skill

```bash
bash ~/.agents/skills/writing-skills/scripts/skill-test.sh tests/n-tdd/bug-under-time-pressure.md               # red: without the skill
bash ~/.agents/skills/writing-skills/scripts/skill-test.sh tests/n-tdd/bug-under-time-pressure.md skills/n-tdd  # green: with it
```

Codex runs each rep in a fresh context, and a second Codex call grades it against the scenario's `PASS:` line. Answers land in `tests/.runs/`. Method: `writing-skills` → `references/testing.md`.

## Promote

A skill replaces its live twin only when its scenario fails without the skill and passes with it in most reps. Then copy it into the plugin, bump the three manifests, and add a CHANGELOG line.
