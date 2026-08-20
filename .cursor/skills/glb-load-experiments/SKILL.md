---
name: glb-load-experiments
description: >-
  Use when the user starts /glb-load-experiments, AUTONOMOUS=1, checkpoint,
  or the GLB load-bench experiment campaign. Main-chat orchestrator only.
disable-model-invocation: true
---

# GLB load-time experiments

Orchestrator only. Rules: [references/PROTOCOL.md](references/PROTOCOL.md). Workers: `.cursor/agents/glb-load-*`. Data: `experiments/`.

1. `scripts/cold-start.sh`
2. Abandon if PROTOCOL Stop says so — else experiment loop in PROTOCOL
3. Checkpoint when PROTOCOL says → integrator → benchmarker `mode=checkpoint` → `update-residual-map.sh`
4. Summarize with `scripts/summarize-bench-log.sh` (never paste xcodebuild)

**Output:** phase, champion, residual top-3, `accepted_queue` len, `reject_only_batches`, next action.
