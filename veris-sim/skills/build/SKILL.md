---
name: build
description: Build a feature against the vendor's twin - measure every vendor claim the task rests on before designing, prove the change with a receipt from veris run, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Build the feature in the request that came with this command: a GitHub issue URL or
number, or free text. Not done until every gate below is met and the PR says so.

Needs `.veris/twin.yaml` in the repository. If it is missing, stop: `setup` runs first.

Three rules, always:

- Never modify the vendor call to make a test pass: a green earned that way proves
  the test changed, not the code. Never point the code at a sandbox, except on a
  repository wired without the proxy, where the variables that point it there are the
  ones production sets ([../veris-reference/direct.md](../veris-reference/direct.md)).
- Anything the task says about the vendor is a **claim** until the twin answers it.
  Vendor documentation is a claim too.
- Never promote a sandbox from this command.

## The task

A GitHub reference: `gh issue view <ref> --json title,body,comments`. Free text: the
request as it arrived. Quote it, whichever it is, then list every claim it makes about
the vendor: what it supports, what a field means, what a repeat does.

Then say where the vendor boundary sits. A feature with no vendor claim on the path:
verify it the repository's own way, and spend the twin on one end-to-end run of the
changed flow. That one run is a floor, not a discount: a task that drove nothing
through the twin has left the change unproven. A feature that rests on what the
vendor does gets every gate.

Read `.veris/NOTES.md` first. It holds what earlier tasks measured; do not measure
it again. Append what you measure here that a later task will need.

Keep the conversation small. Anything that reads wide or returns long, a code survey,
a full test-suite run, any output past a screenful, goes to a subagent where one
exists; keep the answer, not the transcript. Where none exists, bound the read
yourself: name the files, grep for the symbol, read only the hunk, and send long
output to a file you grep rather than into the conversation. Read small things inline:
a row count, one table's shape, a filtered trace.

## Gate 1: every claim measured before the first source edit

1. `veris up`. One sandbox for the whole task. Done when it exits 0 and lists the
   twins. `veris status` shows it any time.
2. `veris sandbox services manual <twin> --raw`. Read it whole, once. (`--raw` puts
   the markdown on stdout; without it the manual renders on stderr.) It is
   authoritative for the credentials the twin accepts, the API versions, the faults
   it can inject, and the `match` keys it supports. It is **not** a list of
   everything the twin implements: read no coverage claim into what it leaves out.
3. The state. `veris sandbox data get <twin>` lists every table with its row count.
   `veris sandbox data schema <twin> --table <t>` shows a table's columns, required
   fields and rules. `veris sandbox data get <twin> <table>` shows what is there.
   Seed what the code path needs, in those shapes, from a JSON file keyed by twin:
   ```
   veris sandbox data add rows.json
   ```
   It prints the twin's own added counts. When a row is refused it prints the twin's
   reasons line by line and stops, with nothing applied for that twin; fix the file
   and add it again. Ids come from the sandbox, never guessed or copied from another
   sandbox. A call that fails because a row was missing has measured nothing. File
   bytes are not rows: seed the owning rows first, then upload the files, as
   [../veris-reference/state.md](../veris-reference/state.md) shows. The state dies
   with its sandbox; resetting it or keeping it is in the same file.
4. For each claim: one probe that answers it. A schema rule, a read of what the
   twin stored, or a direct call at the twin's URL with the credentials the manual
   names. Record the call and the answer. A measurement that contradicts the task is
   the finding, not an error.
5. If the feature is about a failure (a lost response, a limit, a refusal), make it
   happen and drive the current code through it before designing:
   [../veris-reference/faults.md](../veris-reference/faults.md). When the flow does
   not exist yet there is no code to drive: measure the condition itself in step 4
   instead, and drive the change through it at Gate 3.

Write source only after every claim has an answer.

## Gate 2: the identity the design rests on

Before the change keys, looks up or dedupes on any field, read that field's rule in
`veris sandbox data schema <twin> --table <t>`. A field the vendor accepts twice for
distinct records is not an identity; a design keyed on it collapses two records or
misses a repeat.

This binds on every identity, dedup key or external reference the design sends
across the vendor boundary, however the code got it. Prove it against the twin: one
case per component, that component changed and every other one held fixed, and one
case per component that leaves it out of the key altogether. A case that moves two at
once proves nothing about either. Drive them through the **repository's own code path**
under `veris run`, not curl at the twin's URL: a probe you hand-address, with a
credential you invented to send it, measures the twin and not the code the change
ships in, and leaves no receipt behind it. Count the rows the twin stored. Distinct
inputs must leave distinct records; fewer is the design's own defect. A component the
code path always sends cannot be left out without editing the code: record that as the
answer rather than faking it with a hand-made call. The field, each case with the one
component it moved, and the counts go in the PR.

## Implement

As the repository does it: its test conventions, its coverage gate. Run the
repository's full test gate once, in the background, with no timeout of your own, and
poll it to completion; read its result before writing the PR. If the suite runs under
`veris run`, it is a second run against the same sandbox and its traffic lands in the
same ledger: finish it before Gate 3, or give it `--fresh` and a sandbox of its own.
Never kill a running suite to relaunch it; never report a result you did not read.

If the gate cannot run for a reason that predates the change — a collection error in a
file you did not touch, a module the repository does not have — it is not red. Run the
largest subset that does collect, quote the command with every flag it carried, and
put what you left out and why under *limitations and risks*.

## Gate 3: the change through veris run, with a receipt

Run the changed flow from the boundary the task names (the endpoint, worker or
handler) through the sandbox from Gate 1:

```
veris run --patch-bundled-cas --require-service <twin> <the mounts and variables from NOTES.md> -- <the flow>
```

The image and defaults come from `.veris/twin.yaml`; the mounts and variables the app
needs are in `.veris/NOTES.md` under *How to run*. Take them from there, never from a
template: the mount has to land the working tree where the image expects the code,
because a test image usually bakes the repository at a fixed path. Mount it somewhere
else and the run exercises the baked copy, your edit never executes, and the receipt
comes back green with nothing in it saying so. When you find the mount that works,
correct *How to run* in `.veris/NOTES.md`; a fix left only in the PR sends the next
task into the same exit 3.

`--receipt <file>` keeps the receipt as JSON for the PR. Then read what the twin
stored (`veris sandbox data get <twin> <table>`) and what it received
(`veris sandbox trace --tier handler`; `--tier fault` for an injected failure). Both
reads are of *this* run: note the newest trace id for that twin before it and read
back with `--service <twin> --since <id>`, since trace ids are each twin's own
sequence, and find your rows by the ids the run produced, not by where they sit in the
listing. A read taken before the changed code ran says nothing about it.
**Done when the receipt shows at least one request to the twin from that run and
the stored state is what the change promises.** Exit 3 means the flow never reached
the sandbox: fix the wiring, never the call. Exit 4 means the sandbox's ledger could
not be read: run it again, then `veris status`. `--strict` makes the receipt a
stronger claim: the code reached nothing but the sandbox.

On a repository wired without the proxy, where the app reads vendor URLs from the
environment ([../veris-reference/direct.md](../veris-reference/direct.md)), the same
gate reads the trace instead of a receipt: note the newest trace id before the run,
drive the flow against the wired sandbox, then
`veris sandbox trace --service <twin> --since <id>` is the run's receipt.

One green proves one path. Before the PR, list every entry point that reaches the
lines you changed: grep the changed symbols for their callers, and the constants
those callers branch on, out to the endpoints, workers and jobs that own them. Say
which of them this run drove. The rest are not covered: name them under
*limitations and risks* with what a caller reaching the change that way still gets.
Also search for branches that duplicate the behaviour instead of calling it: the
same response handled inline, selected by a mode or type switch. A grep for your
symbol cannot find them. Drive each in the green run or list it. In a large
repository this sweep is worth a subagent where one exists: ask for the entry points,
each marked driven or not driven. The matrix shape is in
[../veris-reference/proof.md](../veris-reference/proof.md), **The route and branch
matrix**. Read that section and **The three layers** above it. The ledger and Gate 4
are `fix`'s — a build has no task id and no ledger — but it names each measurement in
the PR body with the same four dispositions.

## The PR

Open a draft the way the repository does. Its body has three sections, in the shape
of [../veris-reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* (each claim, the probe, the receipt line); *what I am assuming rather than
verifying*, and why that is acceptable; *limitations and risks*. Every task premise
that measured false is its own line: the premise, the probe, the answer, never
restated as fact afterwards. Paste the sandbox id. Ids stop resolving once the sandbox
is deleted, so before `veris down` save the rows and trace entries the body cites to
`.veris/evidence/<flow>.json` (`--json` on `veris sandbox data get` and
`veris sandbox trace`) and name that path beside the ids. Whether that file is
committed with the change or only kept on disk is `artifact_policy` in
`.veris/setup.json` (`setup` step 9). Identifiers, counts and excerpts only, never
credentials. Then `veris down`.

When a step needs it: [../veris-reference/faults.md](../veris-reference/faults.md)
for faults, credentials and the clock; [../veris-reference/webhooks.md](../veris-reference/webhooks.md)
when the app receives callbacks; [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md)
for what a receipt, an exit code or a vendor-shaped error means. Note anything the
twin got wrong or lacked and tell the engineer at the end. Ask before sending
repository code anywhere new.
