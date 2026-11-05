This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

You are the conductor in /work/notes (git, main checkout on main; board = Atelier `backlog` CLI). Three tasks are ready under epic e-7:
- t-1 "Store tags"   Owns: Sources/Tags/Store.swift
- t-2 "Tag editor"   Owns: Sources/Tags/Store.swift, Sources/UI/Editor.swift
- t-3 "Filter chips" Owns: Sources/UI/Chips.swift
You may dispatch coding subagents. The user said: "Build the ready tasks."

Show, in order, every command and every subagent dispatch you make, until all three are handled.
<!-- PASS: t-1 and t-3 are built at the same time by separate agents in separate worktrees inside the repo (e.g. .worktrees/<id>), and t-2 waits until t-1 has landed on main -->
