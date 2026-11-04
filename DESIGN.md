# Design

**The model is the product.** Quiet native chrome, the file in focus. When this doc and the app
disagree, the code wins.

## Principles

- **Native macOS.** System glass, fonts, light/dark and accessibility settings. Every command
  is in the menu bar with its shortcut; in-window controls are a subset of the same actions.
- **Setting or view state.** A Settings value decides how new windows start. A window's view
  state is how you look at this file now. One owner per control; live chrome never rewrites
  Settings.
- **Show what the file has.** No UI for data the file lacks: hide it, don't grey it out. A
  simple mesh gets calm chrome; a rich file may show more.
- **Honest.** The sidebar and inspector describe the file's JSON, not what the renderer kept.
  Validation issues (the file is wrong) and viewer limits (we didn't draw it) are shown
  separately. Dimensions and stats come from the real model.
- **Same picture everywhere.** The Khronos Sample Viewer is the reference, on every surface.
- **Fast first frame.** Geometry first; lighting warms in after. Center + fit by default, easy
  to turn off (then the model sits at its authored origin).
- **Color means type.** Accent only for selection and active state; tints encode glTF roles.

## Non-goals

- Not an editor. Nothing writes the file. Hide/solo, picking, gizmos and the skeleton overlay are
  per-window view state; Quick Look and thumbnails show the rest pose with nothing hidden.
- No renderer setting, no duplicate settings, no control the renderer cannot drive (morph weight
  sliders, double-sided override, custom environment).
