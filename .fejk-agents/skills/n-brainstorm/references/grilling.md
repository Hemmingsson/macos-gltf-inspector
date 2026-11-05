# Grilling rounds

- **Design tree:** every decision branches into the decisions that hang off it.
- **Frontier:** the decisions whose prerequisites are settled — the ones you can ask now without guessing at answers you haven't heard.
- Ask the **whole frontier** in one round. A question that depends on another open question waits for a later round.
- Word each question so "yes" accepts your recommendation. Name the options when they can be named, with what each trades off.
- A fact you are still looking up is an unsettled prerequisite: ask the rest of the frontier now.
- Recompute the frontier after each round. **Done** when it is empty and the user confirms your playback.

Format:

```text
❓ **Q1 – <title>**: <question; the options and what each trades off>

➡️ <recommended answer, and why>

---

❓ **Q2 – <title>**: …

➡️ …
```

In Claude Code, `AskUserQuestion` (up to 4 questions, recommended option first) is a good carrier for a round of up to four closed questions.
