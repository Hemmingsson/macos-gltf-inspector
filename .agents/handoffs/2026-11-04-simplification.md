# Simplification pass: one renderer, one document model, one owner for window state

Branch `refactor/simplify`, worktree `.worktrees/simplify`, from `main` at `12cb015`. Follows
[`.agents/prompts/simplify-repository.md`](../prompts/simplify-repository.md).

## Target, as built

- **GLTFCore** says what a file contains (`GLTFDocument` from the JSON, the validator, the look
  vocabulary, App Group settings).
- **Renderer** draws it: `MetalRenderer` (Khronos port) inside `ModelView`, mounted by
  `ModelCanvas` in the window and Quick Look and used off screen by `ThumbnailRenderer`.
- **The app** shows it: `DocumentWindowModel` (file, document, validation) and `ViewState`
  (everything about how this window shows it), with views that bind to those two directly.

No protocols between layers, no second renderer, no second copy of the document model.

## Not done, on purpose

- The renderer internals (`MetalRenderer`, scene loader, shaders) are unchanged apart from
  API trimming: they are the accurate part, guarded by the reference images.
- `main`'s uncommitted work at branch time (menu symbols in `ViewMenuCommands` / `ViewModeMenu`,
  `DSGlassMenuButton`, `MenuSymbol.swift`, a `pbr.metal` / overlay change, deleted docs) is not in
  this branch. Files it touched moved or were rewritten here, so expect to port it by hand.

## Found along the way

Fixed here: animation rows and validator pointers disagreed on indices when a file had an empty
clip (the parser dropped it); a skin-only node opened the skin with its node index.

Still open:

- `GLTFValidatorCorpusTests`: `ui-showcase.glb` reports `SKIN_SKELETON_INVALID` (predates this
  branch).
- With the inspector open on a narrow window the toolbar clusters overlap (also on `main`).
- First frame waits for the lighting bake to decompress (DESIGN.md wants IBL after first paint).
