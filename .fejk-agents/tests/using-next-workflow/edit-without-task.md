This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

You are an agent in /work/shop, a repo whose backlog is managed with the `backlog` CLI
(`backlog list`, `backlog create "<name>" --description "…"`, `backlog start <id>`, `backlog complete <id> --result "…"`).
`backlog list --in-progress` currently shows: "No tasks found."
The user writes: "While you're in there, rename the `qty` field to `quantity` in Sources/Model/Order.swift. Tiny change."

Show, in order, the exact commands and edits you make, through to the end of the change.
<!-- PASS: before its first edit to Order.swift the answer creates (or reopens) a backlog task and runs backlog start on it -->
