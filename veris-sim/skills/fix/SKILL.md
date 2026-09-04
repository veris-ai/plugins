---
name: fix
description: Fix a defect against the vendor's twin - reproduce the failure the issue describes through the repository's own code before designing, prove it closed with a receipt from veris run, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Fix the defect in the request that came with this command: a GitHub issue URL or
number, or free text. Not done until every gate below is met and the PR says so.

Needs `.veris/twin.yaml` in the repository. If it is missing, stop: `setup` runs first.

Three rules, always:

- Never modify the vendor call to make a test pass, and never point the code at a
  sandbox — except on a repository wired without the proxy, where the variables that
  point it there are the ones production sets
  ([../veris-reference/direct.md](../veris-reference/direct.md)).
- Anything the issue says about the vendor is a **claim** until the twin answers it.
  The issue's own diagnosis is a claim.
- Never promote a sandbox from this command.

## The task

A GitHub reference: `gh issue view <ref> --json title,body,comments`. Quote it. Name
the failure in one sentence: what the vendor did, what the code did next.

**The diagnosis, before any sandbox.** Read the code path the issue names and list
every distinct defect that could produce the symptom: the vendor's failures, and the
repository's own (state lost between requests, a queue, a cache, a race), which no
twin can represent. The twin confirms a diagnosis chosen from code evidence; it does
not choose it. In a large repository, hand this survey to a subagent where one
exists and keep the list, each candidate with its file and line.

Then say where the vendor boundary sits. A defect with no vendor claim on the path:
verify it the repository's own way, and spend the twin on one end-to-end run of the
changed flow. A defect that rests on what the vendor does gets every gate.

Read `.veris/NOTES.md` first. Append what you measure here that outlives the task.

Keep the conversation small. Anything that reads wide or returns long, the code
survey above, a full test-suite run, any output past a screenful, goes to a subagent
where one exists; keep the answer, not the transcript. Where none exists, bound the
read yourself: name the files, grep for the symbol, read only the hunk, and send long
output to a file you grep rather than into the conversation. Read small things
inline: a row count, one table's shape, a filtered trace.

**Pin the base before the first edit:**
`sh .veris/bin/record.sh base --task <id> --paths <the files the diagnosis implicates>`.
Gate 4 measures against it. A base chosen once the diff exists is chosen by the
thing being measured. Without `--paths` the script falls back to the source roots in
`.veris/setup.json`, which pins far more than the task touches. `setup` staged the
two scripts into `.veris/bin/`; if they are missing, run `setup` again. The task's
record and ledger live under `.veris/tasks/<task-id>/`.

## Gate 1: the failure reproduced before the first source edit

1. `veris up`. One sandbox for the whole task. Done when it exits 0 and lists the
   twins. It prints an expiry, and nothing extends a running sandbox: `veris sandbox`
   has no extend verb, and `--ttl` only sets the life of a new one. So set it when you
   mint it — `veris up --ttl <minutes>` overrides the environment's for this sandbox —
   and weigh what `veris status` says is left against the work still to do before
   starting anything long: every id in Gates 1 to 3 dies with the sandbox.
2. `veris sandbox services manual <twin> --raw`. Read it whole, once. (`--raw` puts
   the markdown on stdout; without it the manual renders on stderr.) Authoritative for
   the credentials, API versions, injectable faults and `match` keys; not a catalogue
   of what the twin implements.
3. The state. `veris sandbox data get <twin>` for the row counts,
   `veris sandbox data schema <twin> --table <t>` for the shapes, then
   `veris sandbox data add rows.json` for what the code path needs. A refused row
   prints the twin's reasons and applies nothing for that twin; fix the file and add
   it again. Ids come from the sandbox, never guessed or copied from another sandbox.
   A call that fails because a row was missing is not the failure the issue
   describes. File bytes are not rows: seed the owning rows first, then upload the
   files, as [../veris-reference/state.md](../veris-reference/state.md) shows. The
   state dies with its sandbox; resetting it or keeping it is in the same file.
4. Make the failure happen. A vendor-side defect: arm a fault row as
   [../veris-reference/faults.md](../veris-reference/faults.md) shows. A repository-side
   defect: reproduce it through the application's own state. If the twin cannot
   represent it, that report is the outcome of this gate, not a reason to change the
   diagnosis. Either way, drive the **repository's own code path**, unchanged, through it:
   ```
   veris run --patch-bundled-cas --require-service <twin> <the mounts from NOTES.md> -- <the flow>
   ```
   The image and `require_service` default come from `.veris/twin.yaml`; the mounts
   and variables the app needs are in `.veris/NOTES.md` under *How to run*. That line
   is a claim like any other; a mount `setup` wrote down but never ran is not
   evidence. It goes wrong three ways: it lands the repository where the image's
   interpreter does not look (`-v "$PWD:/work" -w /work` over an image built at
   `/app`), it shadows the image's virtual environment, or it is missing. Each buys an
   exit 3 and nothing else. To have the record write down what the run did, wrap it:
   `sh .veris/bin/record.sh red --task <id> --expect <mode> -- veris run ...`, where
   `--expect` is `nonzero`, `assertion=<text>`, `predicate=<cmd>` or `baseline`. It
   refuses a run whose pinned source has moved.

   If that run exits 3 on wiring, read the command's own output, then check the mount
   against the image itself before suspecting anything else:
   `docker run --rm --entrypoint sh <image> -c 'pwd; ls; command -v <the runner>'`.
   When you find the mount that works, correct *How to run*; a fix buried in a task
   note below it sends the next reader into the same exit 3.
5. Read the ledger. `veris sandbox data get <twin> <table>` for what the twin stored;
   `veris sandbox trace --tier fault` for the injected exchange, `--tier handler` for
   the traffic around it. **Not done until they show the outcome the issue
   describes** (the duplicate row, the lost write, the wrong state) with ids and
   counts you can quote.

The order is the evidence: the red run happens against unmodified code, before the
first edit. A red produced later by stashing the fix proves nothing.

If the failure will not reproduce, that is the finding: report what the twin did
instead, with the trace, and stop before changing code.

## Gate 2: the identity the fix rests on

Before the fix keys, looks up or dedupes on any field, read that field's rule in
`veris sandbox data schema <twin> --table <t>`. A field the vendor accepts twice for
distinct records is not an identity; a fix keyed on it trades one failure for another.

Prove it against the twin: one case per component, that component changed and every
other one held fixed, and one case per component that leaves it out of the key
altogether. A case that moves two at once proves nothing about either. Drive them
through the **repository's own code path** under `veris run`, not curl at the twin's
URL: a probe you hand-address, with a credential you invented to send it, measures the
twin and not the code the fix ships in, and leaves no receipt behind it. Count the
rows stored. Distinct inputs must leave distinct records. A component the code path
always sends cannot be left out without editing the code: record that as the answer
rather than faking it with a hand-made call. The field, each case with the one
component it moved, and the counts go in the PR.

## Implement

As the repository does it. Run its full test gate once, in the background, with no
timeout of your own, and poll it to completion; read the result before writing the
PR. If the suite runs under `veris run`, it is a second run against the same sandbox
and its traffic lands in the same ledger: finish it before Gate 3, or give it
`--fresh` and a sandbox of its own. A `--fresh` run that exits 4 keeps its sandbox and
makes it this folder's, so check `veris status` still names the task's sandbox before
Gate 3.

The suite may need mounts the smoke run did not — a fixture tree outside the baked
source, say. An empty receipt and exit 3 because the suite never got as far as running
a test is a wiring finding, not a suite result; that attempt does not count as the
run. If the suite is not green, a failure is only pre-existing if the pinned base
fails it too: measure that, or say in the PR that you argued it from the code and did
not measure it. Never kill a running suite to relaunch it; never report a result you
did not read.

## Gate 3: the same failure, closed, with a receipt

Re-arm the same fault. Drive the same code path through the same sandbox with
`veris run` (`--receipt <file>` keeps the receipt as JSON for the PR; wrapped in
`sh .veris/bin/record.sh green --task <id> --expect <mode> -- veris run ...` the
record writes it down, and every `--expect` inverts: the test passes, the failure
string is gone, the predicate no longer finds the defect). Read the ledger again.
**Done when the receipt shows at least one request to the twin from that run and
the ledger shows what the fix promises**: one row where there were two, the write
recovered, the state right. A suite that cleans up after itself leaves no rows to
read: then the trace is the read-back, `veris sandbox trace --body <id>` for the
request the flow sent and the twin's answer to it, and it goes into
`.veris/tasks/<task-id>/snapshots/` before teardown, because trace ids die with the
sandbox too. Red before, green after, same flow. Exit 3 means the flow never reached
the sandbox: fix the wiring, never the call. Exit 4 means the sandbox's ledger could
not be read: run it again, then `veris status`.

One green proves one path. List every entry point that reaches the changed lines
(callers of the changed symbols, and the constants they branch on, out to the
endpoints, workers and jobs). Say which this run drove; name the rest under
*limitations and risks*. Search for branches that duplicate the behaviour instead of
calling it, which a grep cannot find, and drive or list each one. In a large
repository this sweep is worth a subagent where one exists: ask for the entry points,
each marked driven or not driven.

On a repository wired without the proxy, where the app reads vendor URLs from the
environment ([../veris-reference/direct.md](../veris-reference/direct.md)), every gate
that reads a receipt reads the trace instead: note the newest trace id before the
run, drive the flow against the wired sandbox, then
`veris sandbox trace --service <twin> --since <id>` is that run's receipt.

## Gate 4: the measurements against the diff

Every measurement is one row in the ledger, written when you take it, not
reconstructed at the end. `sh .veris/bin/ledger.sh init --task <id>` prints the
field contract; `sh .veris/bin/ledger.sh check --task <id>` validates the rows.
Before the PR: `sh .veris/bin/ledger.sh --against-diff --task <id>`. It reads the
base pinned at the start and exits 2 on a gate failure. Each row ends as exactly one
of **encoded** (the changed file and symbol that honours it), **non-load-bearing**
(with the different value it could have taken without changing the fix),
**contradicted**, or **unresolved**. The last two fail the gate. A contradiction
means change the code, not the report. The row format is in
[../veris-reference/proof.md](../veris-reference/proof.md).

## The PR

Open a draft the way the repository does. Its body has three sections, in the shape
of [../veris-reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* (the fault armed, the before ledger, the after ledger, the receipt line);
*what I am assuming rather than verifying*; *limitations and risks*, including what
a caller could still do wrong. Every premise that measured false is its own line and
is never restated as fact. Paste the sandbox id. Where the diagnosis, ledger and
record go is `artifact_policy` in `.veris/setup.json` (`setup` step 9): rendered into
the PR body (`pr-body`), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit`). Then `veris down`.

When a step needs it: [../veris-reference/faults.md](../veris-reference/faults.md),
[../veris-reference/webhooks.md](../veris-reference/webhooks.md),
[../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md). Note
anything the twin got wrong or lacked and tell the engineer at the end. Ask before
sending repository code anywhere new.
