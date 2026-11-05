# Epic review (whole range against the spec)

Used by `n-code-reviewer`. Review the range in the brief against the epic's spec. Return findings; edit nothing.

## Passes

1. **Spec**: every acceptance example has a test that went red then green; nothing built that the spec ruled a non-goal.
2. **Correctness**: trace the changed behaviour and its failure paths — persistence, concurrency, error handling, security boundaries.
3. **Seams**: where tasks meet — interfaces used consistently, no duplicated logic between tasks.
4. **Simplicity and reuse**: redundant state, needless wrappers, dead code, an existing helper the change should use.
5. **Performance**, only on a concrete hot path.
6. **Deferred items**: rule on each Minor and ruling listed on the epic — fix before land, or fine as is.

## Reply

```text
Ready: yes | with fixes | no
Critical | Important | Minor — path:line — trigger → consequence — direction
Checks run: …
```

No actionable findings? Say so. Claim only checks you ran.
