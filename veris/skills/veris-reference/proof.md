# What closes a gate: the layer that owns the claim

The first section is read on every task. The rest only when Gate 2 binds.

## The three layers

A claim belongs to exactly one, and each has one admissible proof.

| layer | asserts | closed by | never by |
|---|---|---|---|
| `REPOSITORY` | application behaviour and state | the repository's own code driven end to end, asserting on **state read back** | a call-shape assertion against a stub |
| `TWIN` | **what this twin produced in this sandbox** | a row from `veris sandbox data get <twin> <table>` or an exchange from `veris sandbox trace`, with ids **and a saved excerpt** | any mock; a stubbed provider; another sandbox |
| `VENDOR_CONTRACT` | what the vendor's documentation promises | the page, quoted, with its URL, or *silent*, recorded as silent | another provider's behaviour; memory |

That the traffic arrived at all is not a ledger row: it is the receipt, and a
gate already refuses to close without it.

**The twin is not the vendor.** It is strong evidence about the vendor, not the
same thing. Never write "I measured" unqualified for something a twin produced.

**Documentation corroborates, contradicts, or is silent.** Silence is not
agreement: a design that needs an unpromised behaviour rests on a premise. Name it.

**One row, one layer.** *"A retry does not charge twice"* is not one claim. It
is a claim about the repository's code, one about what this twin stored, and one
about what the vendor documents. Proving one and asserting all three is how a
mock becomes a vendor proof.

**Mocks are branch coverage**, never the evidence a `TWIN` claim closes on.

**When the twin cannot represent the case**, the claim is not downgraded to fit:
it is a `REPOSITORY` claim with repository proof, or it is `UNRESOLVED`, and
that is the finding.

## The ledger, and the four dispositions

This section is `fix`'s: the ledger is what its Gate 4 checks. A `build` has no
ledger, no task id and no Gate 4. Its measurements go in the PR body, and the
dispositions below are how it names each one there.

The scripts live in `.veris/bin/` once `setup` step 9 has run.
`sh .veris/bin/ledger.sh init --task <id>` prints the field contract;
`sh .veris/bin/ledger.sh add --task <id> --row '<json>'` appends one row and
stamps the time it was written; `check` validates the rows as you go;
`--against-diff` closes Gates 4 and 5 and exits 2 on a gate failure. `--task`
may be omitted when `VERIS_TASK_ID` is set. The ledger lives under
`.veris/tasks/<task-id>/`.

**Append each row when you take the measurement.** A ledger typed out at the end
is a summary of the task, and a summary is exactly the artifact that cannot
contradict the code: three or more rows sharing one `written_at` fail the gate.
The base likewise comes only from the `record.json` that `record.sh base` pinned
before the first edit; `--against-diff` refuses to run without it and takes no
`--base`, because a base the change names at gate time is chosen by the thing
being measured.

Every measurement ends as one of:

- **`ENCODED`**: name the changed file and the symbol or decision honouring it,
  and carry two more fields. **`falsifier`**: the concrete input, or the state,
  under which the shipped code would violate this measurement — or, when the
  decision leans on an escape hatch, the reason that hatch is unreachable, named
  in the shipped code. **`run_ref`**: the run that drove that falsifier through
  the shipping path, with the twin read back. Both are required and neither is
  a warning.
- **`NON_LOAD_BEARING`**: carries a **counterfactual**, the different value this
  measurement could have taken *without changing the promised outcome*. If you
  cannot write one, it is load-bearing and this is not the row.
- **`CONTRADICTED`**: the change does what the measurement says is wrong.
  **A gate failure. Change the code, never the report.**
- **`UNRESOLVED`**: never settled. A gate failure.

One row is not a measurement but a drive: `row_type: "DEFAULT_PATH"`, with
`caller_unchanged: true` and a `run_ref`. It records the call the task names,
made the way a caller that changed nothing makes it, driven twice, with what the
twin stored counted across both. The gate does not close without one. A
mechanism that engages only for a caller that passes something new has not
changed what the application does.

Ids stop resolving when the sandbox is deleted, so a `TWIN` row saves the redacted
excerpt under `.veris/tasks/<task-id>/snapshots/`. A `build` has no task id, so it
saves the same excerpts to `.veris/evidence/<flow>.json`. Save identifiers, paths,
commands and excerpts only, never credentials; the check scans for secret shapes.

The check confirms the ledger is complete, typed and locatable. It **cannot**
tell whether the code obeys a measurement, or whether a sentence smuggles in a
second layer; no pattern match on a row's text could. Writing the falsifier and
driving it is the only step that can, and it is the step whose absence has cost
the most: three times, on three repositories and three vendors, the deciding
fact was measured correctly, written down accurately, marked `ENCODED`, and
contradicted by the code shipped in the same change. Every one of those rows
passed the structural check.

The same asymmetry holds for how an instruction reaches you. A gate stated in
the task text, or arriving on the turn from a session hook, changes work that
the same words in a reference like this one do not: matched runs of one task
put it at 3 of 3 from the task, 2 of 6 from a hook, and 0 of 4 from prose that
was demonstrably read. So an instruction from the engineer's own prompt outranks
this file where the two differ, and these documents carry the procedure rather
than trying to carry the imperative alone.

## The identity, when Gate 2 binds

An identity is a function of what the caller knows. **Name its inputs.** If two
inputs the caller must keep apart map to the same value, that is a collision, and
**dropping an input** is one way to cause one. Joining, normalizing, truncating and
hashing collide; so does projection, and copying discharges nothing.

For retry, idempotency, deduplication or replay, three properties, each proven at
its own layer:

| invariant | the property | usually owned by |
|---|---|---|
| `DUPLICATE_SAFETY` | equivalent retries produce **at most one** external side effect | `TWIN`: count the rows stored |
| `NON_INTERFERENCE` | distinct valid operations are not collapsed, blocked, or made to share an authorization | often `REPOSITORY`: the application's own accounting, which the vendor never sees |
| `LIVENESS` | after a retryable failure the operation **can eventually succeed**: the row *exists*, not merely that no duplicate does | `TWIN`, through the shipping path |

Safety alone reads as success while an operation is permanently stuck. State all
three, or say which does not apply and why.

## The route and branch matrix

A caller grep cannot find a branch that duplicates the behaviour instead of
calling it: that branch is defined by *not* referencing what you changed. From
the changed lines, walk to the files that dispatch to them:

| entry point | dispatcher | predicate + constant | values | driven? |
|---|---|---|---|---|
| | | | | |

Every predicate selecting behaviour for the same request gets a row, with the
value your green run carried. If you cannot say which side of a predicate your run
drove, that predicate is not covered. **An undriven branch that can reach the same
defect is a gate failure; one that cannot is a limitation, named.**
