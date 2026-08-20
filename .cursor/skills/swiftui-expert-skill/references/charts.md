> Read this when: implementing or reviewing Swift Charts (`Chart`, marks, selection, Chart3D) or chart VoiceOver / Audio Graph.

# Swift Charts

**Contents**
- [Core & marks](#core--marks)
- [Chart3D / axes / style](#chart3d--axes--style)
- [Accessibility & availability](#accessibility--availability)

## Core & marks

`import Charts`. Models `Identifiable` (or `Chart(data, id:)`). `.value("Label", v)` feeds axes/legend/VO — never `"X"`/`"Y"`. Chart-wide modifiers on `Chart`; mark modifiers on marks. Animate with `withAnimation` + stable ids.

| Mark | Use |
|------|-----|
| `BarMark` | Categories; stack `.standard`/`.normalized`/`.center`/`.unstacked` |
| `LineMark` / `AreaMark` | Series; `yStart`/`yEnd` bands |
| `PointMark` / `RectangleMark` / `RuleMark` | Scatter / heat / goals |
| `SectorMark` (17+) | Pie/donut |

iOS 18+: `*Plot` wrappers; function closures on `LinePlot`/`AreaPlot`. Selection returns **plottable axis value** — map to model. `chartXSelection(value:|range:)`, `chartAngleSelection` for sectors. Annotations: `.annotation(position:)`.

## Chart3D / axes / style

Gate `#available(iOS 26, *)`. 3D marks + `SurfacePlot`; `.chart3DPose(.front)` / azimuth+inclination; `.chart3DCameraProjection(.perspective)` (default orthographic).

Axes: `chartXAxis`/`chartYAxis`, `AxisMarks` (`preset`, `values: .stride`/`desiredCount`), `AxisGridLine`/`Tick`/`ValueLabel`. Scales: `chartXScale(domain:)`. Scroll (17+): `chartScrollableAxes`, `chartXVisibleDomain`, `chartScrollPosition`. Overlay: `ChartProxy` via `chartOverlay`/`chartBackground`/`chartGesture`.

`foregroundStyle(by:)` for series (legend+a11y). Per-mark solid color kills both — override with `chartForegroundStyleScale`.

## Accessibility & availability

Describe Chart / Audio Graph / Chart Detail rotors free from `.value` labels. Custom: `AXChartDescriptorRepresentable` + `.accessibilityChartDescriptor(self)`.

Modifiers changing return type can't live under `if #available` — duplicate `Chart` for fallback.

| OS | APIs |
|----|------|
| 16+ | Chart, core marks, axes, proxy |
| 17+ | SectorMark, selection, scroll, chartGesture |
| 18+ | `*Plot`, function plots |
| 26+ | Chart3D, SurfacePlot, Z-axis |
