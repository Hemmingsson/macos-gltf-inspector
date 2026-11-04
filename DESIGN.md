# glTF Inspector — Design Guidelines

**The model is the product.** Chrome recedes, the file stays in focus, and the user stays in
control of how it's shown. Native macOS, slim, honest.

**What this is.** Enduring principles for *how to think* when designing or iterating — not a
wireframe, not where controls live today, not what's in which column. That belongs in code.
When this doc and the app disagree, **code wins**.

---

## macOS-native

- **System first** — glass, system typography, light/dark and accessibility settings from the OS
  (Reduced Motion, Increase Contrast, …). Icons: prefer a mapped custom glyph (Blender UI icons
  for typed lights, etc.); **SF Symbols are the fallback** when nothing is mapped.
- **Menu bar = the full command set** — every action has a shortcut there. In-window controls are
  the *discoverable* subset; same actions, same shortcuts, one storage path.
- **Distributed, not crammed** — stage / look / camera are different jobs; don't pile unrelated
  actions into one toolbar strip because it fits on a mockup.

## The three-job rule

> Change it because of **this model** → view state. Change it because of **how you always work**
> → a setting.

| Job | Question | Storage |
|---|---|---|
| **App default** | How should *new* windows start? | Settings only |
| **This window** | How am I looking at *this* file right now? | Per-window session |
| **This file** | What does *this asset* contain? | Read from the loaded model |

- **One control, one job.** Never mirror the same switch in Settings and the live chrome with
  separate storage — pick one owner, compute the effective value at render time.
- Settings seed new windows; live chrome does not silently rewrite defaults.

## glTF & the renderer

- **Closest practical 1:1** with the Khronos Sample Viewer, and the same renderer on every
  surface (window, Quick Look, and Finder). Fidelity over DCC breadth.
- **Complexity follows the asset** — a plain mesh should feel calm; a rigged, textured,
  multi-scene file may legitimately expose more. Never the reverse (empty chrome for a rich file,
  or chrome for data that isn't there).
- **Hide, don't disable** — if the file lacks animations, cameras, lights, morphs, maps, or extra
  scenes, omit that UI. Greyed-out placeholders are noise.
- **Honest rendering** — the user must be able to tell *file wrong* from *we didn't render it*.
  Validation and viewer limits are separate stories; nothing silent. The sidebar describes the
  **file JSON**, not what the renderer kept.

## Inspector honesty

The inspector answers *"is the file wrong, or are we?"*

- Surface **validation** (spec / structural issues in the file).
- Surface **viewer limits** (what the renderer could not draw) — a valid file can still look
  wrong in our viewer.
- Read **dimensions and stats from the real model**, not placeholders.
- When the user turns off centering, show the **authored origin** — don't pretend every asset was
  built at the world origin.

## Visual language

- **Quiet chrome** — hairline borders, generous whitespace; accent only for selection and active
  state.
- **Color = meaning** — type tints encode glTF roles (camera, light, material, …), not
  decoration. No rainbow DCC palette.
- **Every control earns its place** — one thousand no's for every yes.

## Defaults & performance

- **Open path is model-only** — first frame shows geometry; lighting and IBL warm in after paint.
  Never block load on environment probes.
- **Sensible defaults, easy override** — most files benefit from center + fit; power users can turn
  them off without fighting the app.

## Non-goals

- Not an editor: no shader debugger, GPU counters, or heavy DCC tooling.
- No second renderer and no renderer setting. Window, Quick Look and Finder use the same one.
- No fake chrome. No duplicate settings. No section for data that isn't in the file.
- No control the renderer cannot drive. Playback, morph weights, hide/solo, double-sided,
  skeleton, a file-light toggle and a custom environment are not part of the product.
