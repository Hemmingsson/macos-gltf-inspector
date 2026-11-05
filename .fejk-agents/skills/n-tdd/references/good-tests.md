# Good tests

- **One behaviour.** "and" in the name → two tests.
- **Name says the behaviour**, in domain words from the glossary: `testEmptyNameGetsPlaceholder`, not `testImport2`.
- **Assert on outcomes the user could observe**, through the public interface. A test that survives a refactor of the internals is a good test.
- **Independent expected values.** Assert against a literal you worked out, never a recomputation of what the code does.
- **Real code over mocks.** Mock only a boundary you do not own (network, clock, GPU). Know a dependency's side effects before mocking it. Assert on your code's behaviour, never on the mock.
- **Test-only code lives in test utilities**, not in production types.
- **Tight loop.** Fast, deterministic, focused while iterating; the full suite once before reporting.
- **Hard to test = hard to use.** Simplify the interface before adding scaffolding.
- **Deep modules.** Prefer testing a small interface over a large implementation; many tests on private helpers is a design smell.
