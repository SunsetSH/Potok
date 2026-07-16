# Senior Development Standards

Apply these rules to every code change. They are stack-independent; use the idioms, tooling, and lifecycle model of the active platform. Prefer a small correct change over a broad refactor.

## Before and during implementation

- Read the relevant contract, existing conventions, and adjacent code before changing it.
- State and preserve the observable contract unless the task explicitly changes it; add a migration or compatibility path when data/contracts already exist.
- For non-trivial work, identify invariants, failure modes, ownership, and a verification path before coding.
- Do not introduce dependencies, abstractions, or architectural rewrites without a concrete need.

## Architecture and state

- Keep presentation, application/use-case, domain, and infrastructure concerns separate. UI does not contain business rules or access persistence directly; domain code does not depend on UI/framework classes.
- Give each module and type one coherent responsibility. Extract only when it improves a real boundary, readability, or testability—not to satisfy an arbitrary line limit.
- Make state ownership, lifecycle, and concurrency rules explicit. Do not allow competing writers or stale async results to overwrite newer state.
- Model important domain concepts with named, typed values—not unstructured maps, magic strings, or scattered flags.

## Correctness, persistence, and resources

- Every mutation must preserve invariants and leave no partial visible state. Use the platform's transaction, atomic replace, or compensating-operation mechanism as appropriate.
- Make externally retried operations idempotent where feasible; deletion, migrations, and recovery paths must tolerate prior partial completion.
- Validate data at system boundaries; validate domain invariants at domain boundaries. `assert` is only for internal programmer invariants.
- Own resources explicitly and release them deterministically: connections, streams, locks, subscriptions, timers, temporary files, and cancellation registrations. Clean up on success, failure, and cancellation.

## Responsiveness and concurrency

- Never block the UI/event loop with disk, database, network, crypto, or expensive CPU work. Use the platform's asynchronous/background mechanism and marshal only UI updates to the UI context.
- Async work must have a defined cancellation, timeout, error, and disposal path. Prevent work from updating a disposed screen or superseded request.
- Surface progress/loading, success, and failure states honestly. Do not fake success or leave controls permanently disabled after failure.

## Errors, security, and observability

- Never silently swallow errors. Handle them at the layer that can recover; otherwise propagate with useful context and preserve the cause.
- Keep expected domain failures distinct from infrastructure/programming failures. Show users an actionable, non-sensitive message; log diagnostic context safely.
- Treat all external input as untrusted. Use parameter binding/encoding instead of string construction; protect secrets with the platform secure storage; never log credentials, tokens, personal data, or plaintext sensitive content.
- Add structured, minimal telemetry/logging around important failures and state-changing operations without exposing private data.

## Code quality and verification

- Use the language's type system and nullability facilities rigorously. Public contracts, error cases, and ownership must be clear from the code.
- Keep names precise; remove dead code; avoid duplication that can drift. Comments explain non-obvious decisions and constraints, not syntax.
- Add or update focused automated tests for changed behavior, especially invariants, failures, retries/cancellation, persistence, and boundary cases.
- Run the relevant formatter, static analysis, build, and tests. Do not call work complete while a new warning, failed check, or known regression remains unexplained.

## .NET MAUI + C# + XAML mapping

For this project, prefer `async`/`await` with `CancellationToken`, DI, nullable reference types, `IDisposable`/`IAsyncDisposable`, platform secure storage, and the MAUI dispatcher for UI-thread updates. Keep View/XAML bindings free of persistence and business logic; place platform-specific code behind application/infrastructure boundaries