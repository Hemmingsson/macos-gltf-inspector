> Read this when: recording an Instruments `.trace` (attach, launch, or stop-file) for SwiftUI hangs or hitches.

# Recording an Instruments Trace

**Contents**
- [Privacy](#privacy)
- [Flows](#flows)
- [Discovery & template](#discovery--template)
- [Chain & failures](#chain--failures)

`scripts/record_trace.py` wraps `xctrace record`: SwiftUI template default (`--template`), stop via Ctrl+C / stop-file / `--time-limit`, JSON device/template discovery, redacted `--env` logging, system-wide acknowledgement gate.

## Privacy

Prefer `--attach` / `--launch`. `--all-processes` needs explicit user approval + `--allow-system-wide-recording`. Avoid secrets in `--env` (wrapper redacts display; other tools may still see argv).

## Flows

```bash
# Attach (Ctrl+C to stop)
python3 "${SKILL_DIR}/scripts/record_trace.py" \
  --device "Name" --attach "App" --output ~/Desktop/session.trace

# Launch from first frame
python3 "${SKILL_DIR}/scripts/record_trace.py" \
  --device "<UDID>" --launch "/path/to/App.app" --output ~/Desktop/launch.trace

# Background + stop-file (poll 0.5s; SIGINT; ≤60s finalize)
python3 "${SKILL_DIR}/scripts/record_trace.py" \
  --attach App --stop-file /tmp/stop-trace --output ~/Desktop/session.trace
# touch /tmp/stop-trace

# Time-boxed
python3 "${SKILL_DIR}/scripts/record_trace.py" \
  --attach App --time-limit 30s --output ~/Desktop/30s.trace
```

## Discovery & template

```bash
python3 "${SKILL_DIR}/scripts/record_trace.py" --list-devices
python3 "${SKILL_DIR}/scripts/record_trace.py" --list-templates
```

Device JSON: `kind` (`devices`, `devices offline`, `simulators`), `name`, `os`, `udid`.

**Hard rule:** `SwiftUI` template fills the SwiftUI lane only on a **physical device or host Mac**. Simulator → use `Time Profiler` (hangs/hitches still work; `swiftui` lane `available: false`). Confirm kind via `--list-devices` before recording. Offline → connect/unlock/trust first.

Approved system-wide:

```bash
python3 "${SKILL_DIR}/scripts/record_trace.py" \
  --all-processes --allow-system-wide-recording \
  --time-limit 30s --output ~/Desktop/system-wide.trace
```

## Chain & failures

Script prints `trace written: <path>` → feed to `analyze_trace.py` (`trace-analysis.md` for `--window` / list modes).

| Failure | Action |
|---------|--------|
| Device offline | Connect/unlock; retry |
| Output exists | New `--output` or delete |
| Attach: app not running | Launch app or use `--launch` |
| Signing/trust | Dev build + trust profile on device |
