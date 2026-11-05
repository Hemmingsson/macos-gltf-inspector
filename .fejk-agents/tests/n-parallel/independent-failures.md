This is a written exercise: the repository below is not on this machine, so run nothing and look for nothing. Answer as if you were in it.

You are in /work/shop (Swift package; board = Atelier `backlog` CLI; task t-50 "Refactor pricing" is in progress). You may dispatch subagents.
After the refactor, `swift test` shows 6 failures in three files that test unrelated areas:
- CheckoutTests.swift: 3 failures (rounding of totals)
- InventorySyncTests.swift: 2 failures (sync never finishes)
- ReceiptPrinterTests.swift: 1 failure (date format)

Show, in order, exactly what you do next.
<!-- PASS: the answer sends one subagent per independent test file (three, dispatched together so they run in parallel), each with a narrow scope and the failing test names, and then runs the full suite after they return -->
