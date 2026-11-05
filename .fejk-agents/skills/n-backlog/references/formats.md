# Pictures on the board

Plain Markdown always works. Pictures beat prose for this user, so every picture comes from a house tool and is embedded near the top.

## Pick a picture

| You want to show | Make it with | Embed |
| --- | --- | --- |
| The feature working | a live preview (HTML/Svelte page, or the running web URL); native app: `capture_video` / a short screen recording | `webview` fence, or a video/image |
| How it will work: flow, states, sequence, architecture, data types | `create-diagram` (SeeCode: `flowchart`, `state`, `sequence`, `architecture`, `uml-class`, `db-schema`, …) | `webview` fence → the `.html` |
| A physical or 3D idea: parts, layers, dimensions | `create-diagram` → SeeCode `isometric`, `exploded`, `isometric-plan` | `webview` fence |
| A UI layout or its variants | `create-wireframe` | `webview` fence |
| An epic's cover | `create-anatomy` (optional) | `webview` fence |
| The app as it is / as it became | capture (below) | `![before](…)` / `![after](…)` |

Save each one in `.atelier/tasks/<id>/` (`diagrams/`, `captures/`, `demo/`, whatever helps), then put it on the task straight away.

## Captures (before / after)

- **Web pages:** the `capture` MCP (`capture_shot`, `capture_element`, `capture_compare`, `capture_video`). Pass `task: <id>` so files land in `.atelier/tasks/<id>/captures/`.
- **Native macOS windows:** the project's harness (skill `macos-app-testing`; in this repo `./scripts/dev.sh run <fixture>` + `screencapture -l`). Save to `.atelier/tasks/<id>/captures/`.
- **Before:** when the task starts, of the surface it will change. **After:** before landing, with the same framing. Crop to the product; no OS or browser chrome.

## Order in a description

````markdown
```webview aspect=16/9
Measure tool, live | .atelier/tasks/ab12cd34/demo/index.html
```

![before](.atelier/tasks/ab12cd34/captures/before.png)

## Why
…
````

## Order in a result

````markdown
![before](.atelier/tasks/ab12cd34/captures/before.png) ![after](.atelier/tasks/ab12cd34/captures/after.png)

```webview aspect=16/9
What changed | .atelier/tasks/ab12cd34/diagrams/change.html
```

**Proof:** `swift test` 42/42; `MeasureTests.testDistanceBetweenVertices` red → green.

## What changed
…
````

A `webview` body is a workspace path (`.html`, `.svelte`, or a folder holding `index.html`) or an `http(s)` URL, never pasted HTML. Optional first line: `Label | path`.
