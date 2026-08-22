# PreviewUI shell — start or resume

You implement Track A in this worktree. Keep taking ready dex tasks until the user interrupts.

```
cwd:  /Users/mattias/dev/glb-preview/.worktrees/ui
branch: ui-rebuild
dex:  .dex   (epic ktpcdb0v)
```

Do **not** edit `.worktrees/features` or import `Shared/` into `PreviewUI`.

## First action

```bash
dex show ktpcdb0v --full
dex list --ready
```

If a task is already `in-progress`, finish that one (`dex show <id> --full`). Else `dex start` the first ready leaf.

## Each leaf

1. Read **this card**. Standing rules live on the epic. Open a PNG/HTML mock only when the card names it.
2. Design source: `UI-REBUILD/DESIGN.md` (what lives where) + `Main@2x.png` / `Inspect@2x.png` / `Main-html/` / `Inspect-html/` (spacing and colour).
3. `PreviewUI/` = seam + views. `PreviewUIShell/` = app + mocks. Generic canvas, no `AnyView`. Crib glass — don't import `Shared/`.
4. Commands: `FocusedValues` + `CommandGroup(after: .sidebar)` — no second `CommandMenu("View")`.
5. Build and open `PreviewUIShell`. Eyeball vs the wireframe. Then:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -scheme PreviewUIShell -destination 'platform=macOS' \
  -derivedDataPath /tmp/PreviewUIShell-dd build
```

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

Chrome DevTools do not apply (native macOS).
