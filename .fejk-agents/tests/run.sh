#!/usr/bin/env bash
# Run red (no skill) and green (with skill) for every scenario, or the ones named.
#   bash tests/run.sh [tests/<skill>/<case>.md ...]      REPS=3  JOBS=8
# Skill under test = the scenario's folder: tests/<skill>/x.md → skills/<skill>; tests/agents/<agent>.md → agents/<agent>.md
set -uo pipefail
cd "$(dirname "$0")/.."
runner="$HOME/.agents/skills/writing-skills/scripts/skill-test.sh"
mkdir -p tests/.log
if [ $# -gt 0 ]; then list=("$@"); else list=($(find tests -mindepth 2 -name '*.md' -not -path '*/.runs/*' | sort)); fi
jobs_file="$(mktemp)"
for sc in "${list[@]}"; do
  dir="$(basename "$(dirname "$sc")")"; name="$(basename "$sc" .md)"
  if [ "$dir" = agents ]; then target="agents/$name.md"; else target="skills/$dir"; fi
  echo "REPS=${REPS:-3} bash $runner $sc > tests/.log/$dir-$name-red.log 2>&1" >> "$jobs_file"
  echo "REPS=${REPS:-3} bash $runner $sc $target > tests/.log/$dir-$name-green.log 2>&1" >> "$jobs_file"
done
tr '\n' '\0' < "$jobs_file" | xargs -0 -P "${JOBS:-8}" -I{} sh -c '{}'
rm -f "$jobs_file"
for f in tests/.log/*.log; do printf '%-48s %s\n' "$(basename "$f" .log)" "$(grep -o '[0-9]*/[0-9]* PASS' "$f")"; done
