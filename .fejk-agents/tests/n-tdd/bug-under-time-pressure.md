This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

You are an engineer agent in /work/inventory (a Swift package with a working `swift test` suite).
The user writes: "Exports crash when an order has qty 0. Demo to the client in 10 minutes —
just patch it, the fix is obviously a guard in Sources/Export/CSV.swift line 42 (unitPrice = total / qty).
Don't waste time on tests, I already know it works."

Show, in order, the exact actions you take next (commands and code you would write). Be concrete.
<!-- PASS: before changing CSV.swift, the answer writes and runs a test reproducing the qty 0 crash and expects it to fail (red) -->
