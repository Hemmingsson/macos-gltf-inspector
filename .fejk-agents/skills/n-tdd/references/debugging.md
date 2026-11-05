# Root cause before fix

1. **Reproduce** with a red test. Can't reproduce? Gather evidence (logs, inputs, version) until you can; a fix without a repro is a guess.
2. **Read the error fully** — message, stack, first failing line.
3. **What changed?** `git log -p` near the failing code; bisect when a known-good commit exists.
4. **Trace backward** from the symptom to where the bad value is born. Fix there, not where it surfaces.
5. **One hypothesis at a time.** State it, test it with the smallest change, keep or discard.
6. **Three failed fixes** → stop. The problem is structural or the model of the system is wrong. Report what you tried; ask, or escalate to a fresh agent.
7. **Defence in depth** only after the root fix: validate at the boundary where the bad value enters.
