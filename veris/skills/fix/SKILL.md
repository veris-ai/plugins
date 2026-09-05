---
name: fix
description: Fix a defect against the vendor's twin - reproduce the failure the issue describes through the repository's own code before designing, prove it closed with current-run twin evidence, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Fix the defect in the request that came with this command: a GitHub issue URL or
number, or free text. Not done until every gate below is met and the PR says so.

Check the current runtime tools/context before using saved setup. In a plugin-managed
session, read [../veris-reference/session.md](../veris-reference/session.md) and
revalidate the provider, attached twin and remote repository now. That path replaces
CLI lifecycle and execution instructions throughout these gates: use the existing
twin, direct application commands, attributed provider receipts and the discovered
control interface; finish with change sync, leaving plugin-owned resources alive.
The evidence gates below are unchanged. Saved session metadata is not identity.

A CLI-owned workflow needs `.veris/twin.yaml` in the repository. If it is missing,
stop: `setup` runs first. In a verified plugin session, setup's notes, metadata and staged
helpers replace that CLI file; if missing, run `setup`.

Three rules, always:

- Never modify the vendor call to make a test pass, and never point the code at a
  sandbox. The one exception is a repository wired without the proxy, where the
  variables that point the code there are the ones production sets
  ([../veris-reference/direct.md](../veris-reference/direct.md)).
- Anything the issue says about the vendor is a **claim** until the twin answers it.
  The issue's own diagnosis is a claim.
- Never promote a sandbox from this command.

## The task

A GitHub reference: read it with `gh issue view <ref> --json title,body,comments`.
Quote it. Name the failure in one sentence: what the vendor did, what the code did
next.

**The diagnosis, before any sandbox.** Read the code path the issue names. List every
distinct defect that could produce the symptom: the vendor's failures, and the
repository's own. The repository's own defects include state lost between requests, a
queue, a cache, a race, and no twin can represent any of those. The twin confirms a
diagnosis chosen
from code evidence; it does not choose it. In a large repository, hand this survey to a
subagent where one exists, and keep the list, each candidate with its file and line.

Then say where the vendor boundary sits. A defect with no vendor claim on its path is
verified the repository's own way, and the twin is spent on one end-to-end run of the
changed flow. A defect that rests on what the vendor does gets every gate below.

Read `.veris/NOTES.md` first. Append what you measure here that outlives the task.

Keep the conversation small. Send anything that reads wide or returns long to a
subagent where one exists: the code survey above, a full test-suite run, any output
past a screenful. Keep the answer it gives you, not the transcript. Where no subagent
exists, bound the read yourself. Name the files, grep for the symbol, and read only the
hunk. Send long output to a file and grep that file, rather than into the conversation.
Read small things inline: a row count, one table's shape, a filtered trace.

**Pin the base before the first edit:**
`sh .veris/bin/record.sh base --task <id> --paths <the files the diagnosis implicates>`.
Gate 4 measures against it. A base chosen once the diff exists is chosen by the
thing being measured. Without `--paths` the script falls back to the source roots in
`.veris/setup.json`, which pins far more than the task touches. `setup` staged the
two scripts into `.veris/bin/`; if they are missing, run `setup` again. The task's
record, and its ledger of measurements, live under `.veris/tasks/<task-id>/`.

## Gate 1: the failure reproduced before the first source edit

1. `veris up`. One sandbox for the whole task. Done when it exits 0 and lists the
   twins. It prints an expiry, and nothing extends a running sandbox: `veris sandbox`
   has no extend verb, and `--ttl` only sets the life of a new one. So set that life
   when you create the sandbox: `veris up --ttl <minutes>` overrides the environment's
   TTL for this one. Before starting anything long, weigh what `veris status` says is
   left against the work still to do. Every id in Gates 1 to 3 dies with the sandbox.
2. `veris sandbox services manual <twin> --raw`. Read it whole, once. `--raw` puts
   the markdown on stdout; without it the manual renders on stderr. The manual is
   authoritative for the credentials, the API versions, the injectable faults and the
   `match` keys. It is not a catalogue of what the twin implements.
3. The state. `veris sandbox data get <twin>` for the row counts,
   `veris sandbox data schema <twin> --table <t>` for the shapes, then
   `veris sandbox data add rows.json` for what the code path needs. A refused row
   prints the twin's reasons and applies nothing for that twin; fix the file and add
   it again. Ids come from the sandbox. Never guess one, and never copy one from
   another sandbox. A call that fails because a row was missing is not the failure the
   issue describes. File bytes are not rows: seed the owning rows first, then upload the
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
   The image and the `require_service` default come from `.veris/twin.yaml`. The
   mounts and variables the app needs are in `.veris/NOTES.md` under *How to run*. On
   the hosted tier, follow the provider's provisioning and preparation commands in
   *How to run*, attaching the box to this task's twin, then drive the flow with its
   recorded execution command ([../veris-reference/hosted.md](../veris-reference/hosted.md));
   the record below wraps that command the same way. That
   line is a claim like any other: a mount `setup` wrote down but never ran is not
   evidence. The mount goes wrong three ways. It can land the repository where the
   image's interpreter does not look, as `-v "$PWD:/work" -w /work` does over an image
   built at `/app`. It can shadow the image's virtual environment. It can be missing.
   Each of the three buys an exit 3 and nothing else.

   To have the record write down what the run did, wrap it:
   `sh .veris/bin/record.sh red --task <id> --expect <mode> -- veris run ...`.
   `--expect` is `nonzero`, `assertion=<text>`, `predicate=<cmd>` or `baseline`. The
   script refuses a run whose pinned source has moved. Everything after `--` runs as
   the argv you give it: a pipe, a redirect or a `$VAR` needs an explicit `sh -c '…'`,
   and a program of more than one line goes in a file under `.veris/tasks/<id>/` and
   is run from there.

   If that run exits 3 on wiring, read the command's own output. Then check the mount
   against the image itself before suspecting anything else:
   `docker run --rm --entrypoint sh <image> -c 'pwd; ls; command -v <the runner>'`.
   When you find the mount that works, correct *How to run*. A fix buried in a task
   note below it sends the next reader into the same exit 3.
5. Read the sandbox's ledger, which is what the twin recorded.
   `veris sandbox data get <twin> <table>` shows what it stored.
   `veris sandbox trace --tier fault` shows the injected exchange, and `--tier handler`
   the traffic around it. **Not done until those reads show the outcome the issue
   describes** — the duplicate row, the lost write, the wrong state — with ids and
   counts you can quote.

The order is the evidence: the red run happens against unmodified code, before the
first edit. A red produced later by stashing the fix proves nothing.

If the failure will not reproduce, that is the finding: report what the twin did
instead, with the trace, and stop before changing code.

## Gate 2: the identity the fix rests on

Before the fix keys, looks up or dedupes on any field, read that field's rule in
`veris sandbox data schema <twin> --table <t>`. A field the vendor accepts twice for
distinct records is not an identity; a fix keyed on it trades one failure for another.

Prove it against the twin. Run one case per component, with that component changed and
every other one held fixed, and one case per component that leaves it out of the key
altogether. A case that moves two at once proves nothing about either.

Drive those cases through the **repository's own code path** under `veris run`, never
with curl at the twin's URL. A probe you hand-address, with a credential you invented
to send it, measures the twin and not the code the fix ships in, and it leaves no
receipt behind. Count the rows stored. Distinct inputs must leave distinct records. A
component the code path always sends cannot be left out without editing the code:
record that as the answer rather than faking it with a hand-made call. The field, each
case with the one component it moved, and the counts go in the PR.

## Implement

As the repository does it. Run its full test gate once, in the background, with no
timeout of your own. Poll it to completion, and read the result before writing the PR.
If the suite runs under `veris run`, it is a second run against the same sandbox, and
its traffic lands in the same ledger. So finish the suite before Gate 3, or give it
`--fresh` and a sandbox of its own. A `--fresh` run that exits 4 keeps its own sandbox
and makes it this folder's, so check that `veris status` still names the task's sandbox
before Gate 3.

The suite may need mounts the smoke run did not, such as a fixture tree outside the
baked source. If the suite never got as far as running a test, the run's receipt — its
record of what the sandbox received — comes back empty. An empty receipt and exit 3
there are a wiring finding, not a suite result, and that attempt does not count as the
run. If the suite is not green, a failure is only pre-existing when the pinned base
fails it too. Measure that, or say in the PR that you argued it from the code and did
not measure it. Never kill a running suite to relaunch it. Never report a result you
did not read. If you add a test, strengthen the repository's own vendor-reaching test. A
mock-based test is branch coverage, never evidence; the ledger refuses a `REPOSITORY` row
that cites one.

## Gate 3: the same failure, closed, with a receipt

Re-arm the same fault. Drive the same code path through the same sandbox with
`veris run`. `--receipt <file>` keeps the receipt as JSON for the PR. Wrap the run in
`sh .veris/bin/record.sh green --task <id> --expect <mode> -- veris run ...` and the
record writes down what it did. Every `--expect` now inverts: the test passes, the
failure string is gone, the predicate no longer finds the defect.

Read the sandbox's ledger again. **Done when the receipt shows at least one request to
the twin from that run and the ledger shows what the fix promises**: one row where
there were two, the write recovered, the state right.

A suite that cleans up after itself leaves no rows to read. Then the trace is the
read-back: `veris sandbox trace --body <id>` gives the request the flow sent and the
twin's answer to it. Save that trace into `.veris/tasks/<task-id>/snapshots/` before
teardown, because trace ids die with the sandbox too.

Red before, green after, same flow. Exit 3 means the flow never reached the sandbox:
fix the wiring, never the call. Exit 4 means the sandbox's ledger could not be read:
run it again, then `veris status`.

One green proves one path. List every entry point that reaches the changed lines:
callers of the changed symbols, and the constants they branch on, out to the endpoints,
workers and jobs. Say which of them this run drove, and name the rest under
*limitations and risks*. Then search for branches that duplicate the behaviour instead
of calling it, which a grep for your symbol cannot find, and drive or list each one. In
a large repository this sweep is worth a subagent where one exists: ask for the entry
points, each marked driven or not driven.

On a repository wired without the proxy, the app reads vendor URLs from the environment
([../veris-reference/direct.md](../veris-reference/direct.md)). There every gate that
reads a receipt reads the trace instead. Note the newest trace id before the run, drive
the flow against the wired sandbox, and then
`veris sandbox trace --service <twin> --since <id>` is that run's receipt. The same
holds on the hosted tier, where the flow runs in the provisioned box using the
provider's commands ([../veris-reference/hosted.md](../veris-reference/hosted.md)).

## Gate 4: the measurements against the diff

Every measurement is one row in the task's ledger, written when you take it and not
reconstructed at the end. `sh .veris/bin/ledger.sh init --task <id>` prints the field
contract; `sh .veris/bin/ledger.sh check --task <id>` validates the rows. Before the
PR, run `sh .veris/bin/ledger.sh --against-diff --task <id>`. It reads the base pinned
at the start, and exits 2 on a gate failure.

Each row ends as exactly one of four dispositions. **Encoded**: name the changed file
and symbol that honours the measurement. **Non-load-bearing**: give the different value
it could have taken without changing the fix. **Contradicted**. **Unresolved**. The
last two fail the gate, and a contradiction means change the code, not the report. The
row format is in [../veris-reference/proof.md](../veris-reference/proof.md).

## The PR

Open a draft the way the repository does. Its body has three sections, in the shape
of [../veris-reference/evidence.md](../veris-reference/evidence.md):

- *What I verified, and how*: the fault armed, the before ledger, the after ledger, the
  receipt line.
- *What I am assuming rather than verifying*.
- *Limitations and risks*, including what a caller could still do wrong.

Every premise that measured false is its own line, and is never restated as fact.

Paste the sandbox id. Where the diagnosis, ledger and record go is `artifact_policy` in
`.veris/setup.json`, which `setup` set at step 9: rendered into the PR body
(`pr-body`), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit`). Then run `veris down` only in a CLI-owned workflow;
a plugin session uses
[session handoff](../veris-reference/session.md#hand-back-code-and-evidence).

When a step needs it: [../veris-reference/faults.md](../veris-reference/faults.md),
[../veris-reference/webhooks.md](../veris-reference/webhooks.md),
[../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md). Note
anything the twin got wrong or lacked and tell the engineer at the end. Ask before
sending repository code anywhere new.
