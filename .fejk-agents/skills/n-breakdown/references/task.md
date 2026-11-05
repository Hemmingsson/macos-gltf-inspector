# Task shape

Name: one plain line. Description: the sections below, with the most visual thing on top ([pictures on top](../../n-backlog/SKILL.md#pictures-on-top)). Require the information, not the exact headings; a subtask (L2) may be three lines.

````markdown
```webview aspect=16/9
<demo, diagram or wireframe of the target> | .atelier/tasks/<id>/…
```

![before](.atelier/tasks/<id>/captures/before.png)   ← visible change only

## Why
One or two sentences. Spec: epic `<epic-id>`, example A3.

## Scope
- Owns: `path/a`, `path/b` (files this task may change)
- Out: …

## Acceptance tests — write each red before any code
- `FooTests.testRejectsEmptyName` — A3: given …, when …, then …
- Proof rung: unit | in-process | real surface (+ capture)

## Done when
- Observable outcome, checkable by a reviewer.

## Notes
Hints, not micro-steps. Rulings land here during build.
````

## Proof rung

Pick the lowest rung that proves the claim:

| Change | Rung |
| --- | --- |
| Logic, parsing, contracts | unit test |
| Wiring across modules | in-process / integration test |
| Pixels, layout, motion | reference image or a capture of the real surface |
| Config, CLI, docs | command outcome, links resolve |

Visual-only work with no testable seam names its capture or reference image as the red check.

## Example

```bash
backlog create "Reject empty model names on import" --parent <epic> --description "$(cat <<'EOF'
![before](.atelier/tasks/k3x9w2ab/captures/outline-empty-name.png)

## Why
Empty names crash the outline. Spec: epic `k3x9w2ab`, example A3.

## Scope
- Owns: `GLTFCore/Import/NameRules.swift`, `GLTFInspectorTests/NameRulesTests.swift`

## Acceptance tests — write each red before any code
- `NameRulesTests.testEmptyNameGetsPlaceholder` — given a node with name "", when imported, then the outline shows "Node 3".
- Proof rung: unit

## Done when
- Empty and whitespace names get "Node <index>"; suite green.
EOF
)"
```
