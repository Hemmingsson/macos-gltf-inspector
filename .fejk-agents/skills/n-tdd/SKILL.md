---
name: n-tdd
description: Red-green-refactor for every feature, bug fix, or behaviour change. Use before writing production code, and when fixing a bug.
---

# n-tdd

Production code exists only to turn a red test green. If you did not watch it fail, you do not know it tests the right thing.

## The loop (per acceptance test)

1. **Red.** At the seam the spec or task names (none named: the highest existing test seam), write one test for one behaviour, named for that behaviour, against real code. Before running it, name the production change that would make it pass.
2. **Watch red.** Run it. It fails, for the expected reason (behaviour missing — not a typo, not a compile error elsewhere). Passes already? It tests existing behaviour; fix the test.
3. **Green.** Write the least code that passes. Nothing the test does not ask for.
4. **Watch green.** Run the focused test, then the project's whole suite. Output pristine. Any red you see goes in your report by name, yours or not.
5. **Refactor** while green. No new behaviour.

Code written before its test is deleted and rewritten from the test.

## Bug branch

Reproduce first: a red test that fails the way the bug report says. Then find the root cause ([debugging.md](references/debugging.md)), fix, watch green. No fix without a repro test.

## Proof

Record on the task: the red command + failing line, the green command + pass count (`n-verify`). The rung (unit / integration / real surface) is the one the task names. Visual work: the reference image or capture is the red check. Put captures and diagrams on the task as you make them (`n-backlog`).

**Done when** every acceptance test on the task went red then green this turn, and the full suite is green.

Spike the user approved: no tests; it stays throwaway. Config and generated code: a command outcome is the check.

Writing a test: [good-tests.md](references/good-tests.md).
