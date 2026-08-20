> Read this when: analyzing an Instruments `.trace` for hangs, hitches, SwiftUI updates, or high-severity events.

# Instruments Trace Analysis

**Contents**
- [Invoke & CLI](#invoke--cli)
- [Composition](#composition)
- [JSON shape](#json-shape)
- [Interpretation](#interpretation)
- [Output format](#output-format)

Parser reads Time Profiler, Hangs, Animation Hitches, SwiftUI updates, cause graph. Modes: full analysis, `--list-logs`, `--list-signposts`, `--fanin-for`, plus `--window`. Source file optional — cite lines if present.

## Invoke & CLI

Trigger on `.trace` path, hang/hitch/jank talk, or “after/before/during” a log/signpost.

```bash
# Full
python3 "${SKILL_DIR}/scripts/analyze_trace.py" \
  --trace "/path/to/file.trace" --top 10 --top-hitches 5 \
  [--window START_MS:END_MS] [--run N] --json-only
# --output <path> → .json + .md; --markdown-only for chat digest
# Multi-run traces need --run; --list-runs dumps metadata

# Logs
python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> --list-logs \
  [--log-subsystem …] [--log-category …] [--log-type Fault] \
  [--log-message-contains "…"] [--log-limit 10] [--window …]
# → { logs:[{time_ms,type,subsystem,category,process,message,format_string}], count }

# Signposts
python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> --list-signposts \
  [--signpost-name-contains …] [--signpost-subsystem …] [--signpost-category …]
# → { intervals:[{start_ms,end_ms,duration_ms,name,…}], events:[…] }

# Fan-in (who invalidates this view?)
python3 "${SKILL_DIR}/scripts/analyze_trace.py" --trace <path> \
  --fanin-for "TextStyleModifier" [--window …] [--top 10]
```

Filters AND-combined; substring matches case-insensitive. Needs Python 3 stdlib + `/usr/bin/xctrace`.

## Composition

1. Discover via `--list-logs` / `--list-signposts`
2. Build `--window START:END` from `time_ms` or `start_ms`/`end_ms`
3. Full analysis with `--window`

After log → `[time_ms, duration_s×1000]`. Between logs → `[first, second]`. During signpost → `[start_ms, end_ms]`.

## JSON shape

Lanes: `time-profiler` (top_offenders: symbol/weight), `hangs` (duration buckets), `hitches` (narrative, system vs app), `swiftui` (severity/update_type breakdown, high_severity_events), `swiftui-causes` (top_sources / top_destinations).

`correlations[]`: hang/hitch trigger + `time_profiler_main_thread` (`main_running_coverage_pct`, `hot_symbols`) + `swiftui_overlapping_updates`.

## Interpretation

### `main_running_coverage_pct`

| Coverage | Meaning | Fix |
|----------|---------|-----|
| < 25% | Main **blocked** (I/O, lock, sync XPC, sleep) | Move off-main; hot_symbols initiate the wait |
| ≥ 75% | Main **CPU-bound** | Fix hot_symbols; hoist body work |
| 25–75% | Mix | Report both |

### High-severity → route

| description | Route |
|-------------|-------|
| `onChange` / `Gesture` / `Action Callback` | `performance-patterns.md` (+ state for onChange) |
| `Update` / `Creation` | `view-structure.md`, `performance-patterns.md` |
| `Layout` | `layout-best-practices.md` |

Map `view` / module-prefixed symbols to source; strip generics. System frames (`swift_`, `CA*`, `__open`, …) → find user caller / API site. Hitch narrative `"Potentially expensive app update(s)"` = app blame; prioritize overlapping SwiftUI updates.

### Cause graph signatures

- `UserDefaultObserver…GraphAttribute.send()` → `@AppStorage` fan-out storm → one high-level read or `@Observable` settings (`state-management.md`)
- `EnvironmentWriter:` high edges → over-applied env modifier (`view-structure.md`)
- `View Creation / Reuse` #1 → ID instability / `AnyView` / conditional swaps (`list-patterns.md`)

`--fanin-for` on recurring high-severity views.

### Prioritize

1. Hangs coverage < 25% (blocking)
2. Hangs coverage ≥ 75% (CPU)
3. Causes sources > ~1k edges (structural)
4. App-narrative hitches + overlapping updates
5. High-severity handlers > ~16ms → `--fanin-for`
6. `swiftui.top_offenders` for extraction / `.equatable()`

## Output format

1. One-line summary (hangs/hitches/high-sev counts)
2. Root-cause paragraphs with evidence + `references/…` citation
3. Numbered plan with file/line cites — edit only if asked
