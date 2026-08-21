# GLB Preview — Design Guidelines

**The model is the product.** Chrome recedes, the file stays in focus, and the user
stays in control of how it's shown. Native macOS, slim, honest.

---

## macOS-native

- Transparent titlebar, hidden title, full-size content — traffic lights sit over the
  sidebar; the file name lives in the sidebar, not a title band.
- **Distributed toolbar**: floating glass pills over the canvas, grouped leading / center /
  trailing — never one crammed bar.
- The **menu bar is the complete set** (every control, with a shortcut); the canvas pills
  are the discoverable subset. Each pill control mirrors a menu item and the same shortcut.
- System everything: glass materials, SF Symbols, system font, light/dark follows the OS.
- Respect Reduced Motion, Increase Contrast, and the appearance setting.

## Where a control lives — the three-job rule

> Change it because of **this model** → view state. Change it because of **how you always
> work** → a setting.

| Job | Home | Examples |
|---|---|---|
| **App default** | **Settings** only | appearance · default backdrop / floor / auto-rotate · auto-play · default camera |
| **This window** | **canvas pills + View menu** | backdrop · floor · auto-rotate · center · view mode · lighting · perspective↔ortho · Fit · camera presets |
| **This file** | **left sidebar** | scenes · cameras · lights · meshes · materials · animations · selection · stats |

- Canvas controls are **per-window and live**; they never rewrite your defaults.
  Settings = defaults for *new* windows.
- The View menu is the **keyboard twin** of the canvas pills — both drive the same
  per-window state, not a second copy.
- **One control, one job.** Never duplicate a switch as both a setting and a live toggle
  and expect them to share storage. Storage is the single source of truth; the render
  computes the effective value.

### Toolbar clusters

- **Left — Stage:** backdrop · floor
- **Center — Look:** view mode · lighting (exposure / IBL / file-vs-studio)
- **Right — Camera:** auto-rotate · center · perspective↔ortho · Fit · camera presets
- Document/output actions (Open in…, screenshot, inspector toggle) sit on the **right-column
  header**, not on the canvas.

## Show only what the model has

Adaptive UI: **hide** controls and sections for things the file doesn't contain — don't show
them disabled or empty.

- No animations → no playback bar, no Animations section.
- No file cameras → no Cameras section (Fit / presets still work as view state).
- No punctual lights → no Lights section; lighting defaults to studio IBL.
- Single scene → no Scene switcher.
- View-mode menu lists **only channels present** (no clearcoat map → no Clearcoat mode).
- Material chips show **only maps that exist**.
- No skin / morphs → no skeleton or morph controls.
- The selection inspector shows **only the fields the node type has** (mesh vs camera vs light).

*Result:* a plain static mesh opens to a calm, near-empty UI; a rigged, animated,
multi-scene file reveals more. Complexity scales with the asset — never the other way.

## Inspector honesty

The inspector answers *"is the file wrong, or are we?"*

- **Validation** warnings surfaced from the glTF validator.
- A **"what our pipeline did"** list — converted spec-gloss, dequantized, file-lights on/off —
  so nothing is silently changed.
- **Center off** reveals the authored origin with an axis gizmo.
- Dimensions and stats read from the real model.

## Sidebar — structure

- Sketch-style quiet section headers; a section appears **only when populated**.
- One monochrome SF Symbol per glTF type, one low-saturation tint per type
  (camera blue · light amber · material purple · animation green · mesh graphite).
  **Color = meaning, not decoration** — no Blender rainbow.
- Hover reveals visibility (eye); Option-click to isolate.

## Defaults & restraint

- **Open path is model-only.** Lighting warms in after first paint — never block the first
  frame on IBL.
- **Center + Fit by default** (corrects most models); the user can turn both off.
- Light theme, hairline borders, generous whitespace; accent used sparingly (selection +
  active toggles).
- Every control earns its place. One thousand no's for every yes.

## Non-goals

- Not an editor: no shader debugger, GPU counters, or heavy DCC tooling.
- No fake chrome. No control that duplicates a setting. No section for data that isn't there.
