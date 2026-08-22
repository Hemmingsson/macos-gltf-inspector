# Engine packs — start or resume

You implement Track B in this worktree. Keep taking ready dex tasks until the user interrupts.

```
cwd:  /Users/mattias/dev/glb-preview/.worktrees/features
branch: engine-features
dex:  .dex   (epic rmz6ux6k)
```

Do **not** edit `.worktrees/ui`, `PreviewUI/`, or `PreviewUIShell/`.

## First action

```bash
dex show rmz6ux6k --full
dex list --ready
```

If a task is already `in-progress`, finish that one (`dex show <id> --full`). Else `dex start` the first ready leaf.

## Each leaf

1. Read **this card** and the files it names. Standing rules live on the epic — don't re-read DESIGN.md unless the card points at a mock.
2. Verify the current Swift. Do not assume `document.lights`, `soloRoot`, or `PreviewDebugMode.Channels`.
3. Implement the smallest proof in the **current** host UI (menu/toggle/test). Feed the future seam; don't invent a parallel API.
4. Follow `AGENTS.md` (no state writes from `View.init` / RealityView `make`/`update`; don't block first paint on IBL).
5. Prove it. Then:

```bash
dex complete <id> --result "$(cat <<'EOF'
## What changed
## Files changed
## Commands run
## Verification
## Browser observations
N/A
## Remaining risks or follow-ups
## Next recommended task
EOF
)"
```

6. Immediately `dex list --ready` and start the next leaf. Loop until interrupted or nothing is ready.

Cube.gltf has no lights/cameras/anims/skins and is centered — fetch a Khronos sample when the card says so.
