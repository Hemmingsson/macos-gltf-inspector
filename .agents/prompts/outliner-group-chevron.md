# Handover: empty groups show only a chevron

## Goal

In the sidebar outliner, an **empty node that has children** (a group) currently shows a
`folder` icon, which turns into a chevron on hover. Drop the folder. A group row should show
**only the chevron**, all the time: pointing right when folded, down when open. Clicking it
folds or unfolds.

Rows with a real type that have children (mesh, camera, light, scene) keep today's behaviour:
they show their type icon and swap to the chevron on hover.

Background and the before/after icons are in
[`.agents/research/2026-11-04-spline-icon-mapping.md`](../research/2026-11-04-spline-icon-mapping.md), section 2.

## Where

- `GLTFInspector/DesignSystem/Components/Content/DSOutlineRow.swift`, `glyphSlot`. Today it
  shows the chevron button only `if let isExpanded, isHovered`. Show it also when
  `role == .empty` and `isExpanded != nil`, hovered or not.
- `GLTFInspector/DesignSystem/Components/Content/DSTypeIcon.swift`. Remove `isGroup` and the
  `folder` case, since nothing will use them, and update the doc comments in both files.
- `GLTFInspector/Sidebar/NodeRow.swift` builds the rows. It should need no change.

## Keep

- SF Symbols only (`chevron.right`, rotated 90° when open, as the hover chevron already does).
  No bundled art.
- Same glyph-slot size (`DS.Metrics.typeIcon`), so titles still line up down the column.
- The chevron uses the label colour on a selected row, like `DSTypeIcon(isSelected:)`.
- VoiceOver: "Expand" / "Collapse" label and actions, as today. ← / → on the keyboard still fold.
- Hover background circle: show it only while the row is hovered, so a list of groups at rest
  doesn't fill up with grey circles.

## Before you start

`DSOutlineRow.swift`, `NodeRow.swift`, `OutlinerList.swift` and `OutlinerTree.swift` may
already have uncommitted changes on `main`. Check `git status` and work on a branch or worktree.

## Done when

- A group row shows a chevron and no folder, hovered or not; it folds on click and with ← / →.
- Mesh, camera, light and scene rows with children are unchanged.
- `./scripts/dev.sh test` passes.
- You've checked it yourself in the running app: `./scripts/dev.sh run <fixture with nested
  empty nodes>`, then take a screenshot of the sidebar (folded, open, hovered, selected) in light
  and dark mode.
