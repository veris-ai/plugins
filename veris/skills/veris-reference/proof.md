# Evidence from normal development

Use this reference when interpreting evidence, investigating retry/identity behavior,
or explicitly collecting an audit record. Ordinary `build` and `fix` tasks do not
require a ledger or a separate proof phase.

## What a test establishes

An application test against the twin can establish several requirements together.
Use its assertions to check the expected response or persisted outcome and its receipt
or attributed trace to confirm the relevant application traffic reached the twin.
A receipt alone establishes traffic, not correctness. A mock checks local behavior,
not the vendor boundary; a direct twin probe checks the twin, not the application.

Reuse an execution that covered the final relevant source/build and conditions.
If the test already reads and asserts the resulting state, another manual read adds
no requirement. Inspect data or traces when needed to establish an unasserted outcome
or diagnose failure. Read only this run's evidence, using returned ids or trace
watermarks; provider sessions follow [session.md](session.md#evidence-from-this-run).
Tests that clean up their rows can assert before cleanup or retain the relevant trace.

Keep claims within their evidence: a repository test establishes application behavior,
a twin observation establishes that sandbox's behavior, and vendor documentation states
a vendor contract. A twin is not the real vendor, and silence in documentation is not
a guarantee. This distinction does not require separate rows for every statement.
If evidence contradicts the implementation, resolve the defect; do not relabel it as
an assumption. If the twin cannot represent a relevant condition, verify the applicable
application behavior and state what remains unverified.

## Retry and identity changes

Use these cases when the task changes retry, deduplication, identity or replay behavior.
Put the applicable assertions in the affected application test; several calls or
scenarios can run in one execution.

| Behavior | Useful case |
|---|---|
| Equivalent retries do not duplicate a side effect | Retry the same logical operation and assert its final state/count |
| Distinct operations stay distinct | Vary the input that distinguishes two valid operations and assert both results exist |
| A retryable failure can recover | Inject the relevant failure, retry through the actual application path, and assert eventual success |

For a key derived from multiple inputs, target plausible collisions or omissions in
the changed derivation. Read a schema rule when a design depends on uniqueness; a
value the vendor accepts for distinct records is not an identity by itself. Do not
expand an unrelated task into a per-field experiment. An unchanged caller and a new
optional caller have different promised behavior: test the one the task specifies,
plus the compatibility behavior the change must preserve.

## Optional audit helpers

Use these only when the engineer requests a detailed audit or an investigation needs
source history and structured measurements. They remain available from
`veris-reference/scripts/`; `setup` step 9 explains optional staging into `.veris/bin/`.

- `record.sh base --task <id> --paths <paths>` pins the declared source. It needs an
  existing Git commit. Use it before a reproduction when that history is needed.
- `record.sh red/green --task <id> --expect <mode> -- <command>` records the actual
  execution, timestamp and expectation. `record.sh block --task <id>` renders it.
  It refuses a red run if the pinned source or build output has moved; do not
  reconstruct a pre-edit history after the fact.
- `ledger.sh init --task <id>` describes the measurement-row contract;
  `ledger.sh check --task <id>` validates rows and retained snapshots.
  `ledger.sh --against-diff --task <id>` uses the recorded base, or an explicitly
  supplied full starting SHA via `--base`. It checks that encoded rows name changed
  files. It cannot determine whether the code obeys a measurement.

The ledger's dispositions are `ENCODED`, `NON_LOAD_BEARING` (with a counterfactual),
`CONTRADICTED` and `UNRESOLVED`. The last two fail its diff check. Twin snapshots live
under `.veris/tasks/<id>/snapshots/`, with hashes so the check can verify them after
the sandbox is gone. Save redacted excerpts and identifiers, never credentials.
Follow the existing artifact policy; these helpers do not require committing a ledger.
