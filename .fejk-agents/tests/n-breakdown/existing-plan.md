This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

Repo /work/notes uses the `backlog` CLI (`backlog create "<name>" --description "…" [--parent <id>] [--blocked-by <id>]`).
There is already a written plan at .agents/plans/2026-11-01-tags.md:

  # Tags
  Goal: users can tag notes and filter the list by tag.
  1. Store tags on Note (array of strings, lowercased, unique).
  2. Tag editor in the note sheet.
  3. Filter chips above the list; selecting one filters notes.
  Done when: tagging and filtering work; tags survive app restart.

The user writes: "Plan's done. Get it onto the board so we can start."

Show exactly what you do next, including every backlog command with its full description text.
<!-- PASS: the answer leaves the plan document as it is; it creates a parent (epic or task) with children under it; and the descriptions name specific acceptance tests to write before code -->
