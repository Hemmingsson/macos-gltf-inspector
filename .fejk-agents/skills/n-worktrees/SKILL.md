---
name: n-worktrees
description: Create, detect, or land a detached worktree at .worktrees/<task-id>. Use before implementation that must leave the main checkout alone, and when landing an approved worktree onto main.
---

# n-worktrees

The main checkout stays on `main`. A task's work lives in `.worktrees/<task-id>`, detached, so there is no branch to create or delete. `backlog` always writes the board in the main checkout.

## Detect

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
git rev-parse --show-superproject-working-tree
```

`GIT_DIR` ≠ `GIT_COMMON`, and the last command prints nothing: you are already in a linked worktree. Use it. Do not create another.

A superproject path means a submodule. Treat that as the main checkout and continue below.

## Make

From the main checkout:

```bash
git check-ignore -q .worktrees || echo ".worktrees/" >> .git/info/exclude
git worktree add --detach .worktrees/<task-id> main
BASE=$(git -C .worktrees/<task-id> rev-parse HEAD)
```

Record `BASE`. Review ranges start there, never at `HEAD~1`.

Run the project's setup and its test command (`AGENTS.md`) in the worktree. Write the result on the task. A red baseline is reported before any edit; later failures are read against it.

`git worktree add` denied by the sandbox: say so, and work in the current checkout. Do not invent a second location.

## Land

Only after the user has approved (`n-full-send`).

```bash
git -C .worktrees/<task-id> rebase main
git merge --ff-only "$(git -C .worktrees/<task-id> rev-parse HEAD)"
git worktree remove .worktrees/<task-id>
```

Never `remove --force` on a dirty tree. Fast-forward `main` only from `n-full-send`, after the user approves.

Rebase conflict: resolve it in the worktree, run the task's tests again, then land. A conflict that changes behaviour stops for the user.
