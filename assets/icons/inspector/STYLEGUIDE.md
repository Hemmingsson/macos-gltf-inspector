# macOS glTF Inspector icon set drawing guide

Start with the closest sibling in the [gallery](README.md). Copy its base shape, size, and position. Change only the mark that carries the new meaning.

## Draw

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"
     viewBox="0 0 24 24" fill="none" stroke="currentColor"
     stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <!-- Geometry -->
</svg>
```

- Keep 1 px from ink to canvas edge and 2 px between separate marks. Measure from the stroke edges.
- Center strokes on their paths. Round right-angle corners by 2 px on shapes 8 px or larger and 1 px on smaller shapes. Keep shared junctions clean.
- Center symmetrical shapes on (12, 12). Balance uneven shapes by eye. Use simple curves and align geometry to the grid where practical.
- Use paths, lines, polygons, polylines, circles, ellipses, or rectangles with geometry attributes only. Keep coordinates to at most three decimal places.

## Match the family

| Idea | Shared shape |
| --- | --- |
| Render mode | One cube. Change its interior edges. |
| Material or texture | Circle for a channel, square for a map. Repeat the channel mark inside both. |
| Camera preset | Square frame. Front has a solid inset and Back has four broken corners. |
| Projection or light | Converging or parallel edges show projection. Rays show how a light shines. |
| Rotation or loop | Auto rotate adds a center ring to Reset view. Loop has an open center and a bottom return arrow. |

## Review and add

1. Show current and proposed icons side by side at **12, 16, and 40 px**. Include nearby siblings. Check spacing, weight, and recognition on light and dark backgrounds.
2. Save the approved SVG here in kebab-case. Update the gallery and [slot map](slots.json).
3. Run `node assets/icons/inspector/build-catalog.mjs` from the project root. Connect the glyph in [InspectorIcons.swift](../../../GLTFInspector/DesignSystem/Icons/InspectorIcons.swift) and check the actual control with `./scripts/dev.sh run <fixture>`.
