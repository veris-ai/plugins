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

- Never modify the vendor call to make a test pass. A green earned that way proves
  the test changed, not the code. Never point the code at a sandbox. The one exception
  is a repository wired without the proxy, where the variables that point the code
  there are the ones production sets
  ([../veris-reference/direct.md](../veris-reference/direct.md)).
- Anything the task says about the vendor is a **claim** until the twin answers it.
  Vendor documentation is a claim too.
- Never promote a sandbox from this command.

## The task

A GitHub reference: read it with `gh issue view <ref> --json title,body,comments`.
Free text: take the request as it arrived. Quote it, whichever it is. Then list every
claim it makes about the vendor: what the vendor supports, what a field means, what a
repeat does.

Then say where the vendor boundary sits. A feature with no vendor claim on its path is
verified the repository's own way, and the twin is spent on one end-to-end run of the
changed flow. That one run is a floor, not a discount: a task that drove nothing
through the twin has left the change unproven. A feature that rests on what the vendor
does gets every gate below.

Read `.veris/NOTES.md` first. It holds what earlier tasks measured; do not measure
it again. Append what you measure here that a later task will need.

Keep the conversation small. Send anything that reads wide or returns long to a
subagent where one exists: a code survey, a full test-suite run, any output past a
screenful. Keep the answer it gives you, not the transcript. Where no subagent exists,
bound the read yourself. Name the files, grep for the symbol, and read only the hunk.
Send long output to a file and grep that file, rather than into the conversation. Read
small things inline: a row count, one table's shape, a filtered trace.

## Gate 1: every claim measured before the first source edit

1. `veris up`. One sandbox for the whole task. Done when it exits 0 and lists the
   twins. `veris status` shows it any time.
2. `veris sandbox services manual <twin> --raw`. Read it whole, once. `--raw` puts
   the markdown on stdout; without it the manual renders on stderr. The manual is
   authoritative for the credentials the twin accepts, the API versions, the faults
   it can inject, and the `match` keys it supports. It is **not** a list of
   everything the twin implements, so read no coverage claim into what it leaves out.
3. The state. `veris sandbox data get <twin>` lists every table with its row count.
   `veris sandbox data schema <twin> --table <t>` shows a table's columns, required
   fields and rules. `veris sandbox data get <twin> <table>` shows what is there.
   Seed what the code path needs, in those shapes, from a JSON file keyed by twin:
   ```
   veris sandbox data add rows.json
   ```
   It prints the twin's own added counts. When a row is refused, it prints the twin's
   reasons line by line and stops, and nothing is applied for that twin; fix the file
   and add it again. Ids come from the sandbox. Never guess one, and never copy one
   from another sandbox. A call that fails because a row was missing has measured
   nothing. File bytes are not rows: seed the owning rows first, then upload them, as
   [../veris-reference/state.md](../veris-reference/state.md) shows. The state dies
   with its sandbox; resetting it or keeping it is in the same file.
4. For each claim: one probe that answers it. A schema rule, a read of what the
   twin stored, or a direct call at the twin's URL with the credentials the manual
   names. Record the call and the answer. A measurement that contradicts the task is
   the finding, not an error.
5. If the feature is about a failure — a lost response, a limit, a refusal — make
   that failure happen and drive the current code through it before designing.
   [../veris-reference/faults.md](../veris-reference/faults.md) shows how. When the
   flow does not exist yet there is no code to drive: measure the condition itself in
   step 4 instead, and drive the change through it at Gate 3.

Write source only after every claim has an answer.

## Gate 2: the identity the design rests on

Before the change keys, looks up or dedupes on any field, read that field's rule in
`veris sandbox data schema <twin> --table <t>`. A field the vendor accepts twice for
distinct records is not an identity; a design keyed on it collapses two records or
misses a repeat.

This binds on every identity, dedup key or external reference the design sends
across the vendor boundary, however the code got it. Prove it against the twin. Run one
case per component, with that component changed and every other one held fixed, and one
case per component that leaves it out of the key altogether. A case that moves two at
once proves nothing about either.

Drive those cases through the **repository's own code path** under `veris run`, never
with curl at the twin's URL. A probe you hand-address, with a credential you invented
to send it, measures the twin and not the code the change ships in, and it leaves no
receipt behind. Count the rows the twin stored. Distinct inputs must leave distinct
records; fewer records is the design's own defect. A component the code path always
sends cannot be left out without editing the code: record that as the answer rather
than faking it with a hand-made call. The field, each case with the one component it
moved, and the counts go in the PR.

## Implement

As the repository does it: its test conventions, its coverage gate. Run the
repository's full test gate once, in the background, with no timeout of your own. Poll
it to completion, and read its result before writing the PR. If the suite runs under
`veris run`, it is a second run against the same sandbox, and its traffic lands in the
same ledger — the sandbox's running record of what it received. So finish the suite
before Gate 3, or give it `--fresh` and a sandbox of its own. Never kill a running
suite to relaunch it. Never report a result you did not read.

If the gate cannot run for a reason that predates the change — a collection error in a
file you did not touch, a module the repository does not have — it is not red. Run the
largest subset that does collect. Quote the command with every flag it carried, and put
what you left out, and why, under *limitations and risks*.

## Gate 3: the change through veris run, with a receipt

Run the changed flow through the sandbox from Gate 1, starting at the boundary the
task names: the endpoint, the worker or the handler.

```
veris run --patch-bundled-cas --require-service <twin> <the mounts and variables from NOTES.md> -- <the flow>
```

The image and defaults come from `.veris/twin.yaml`. The mounts and variables the app
needs are in `.veris/NOTES.md` under *How to run*. Take them from there, never from a
template. The mount has to land the working tree where the image expects the code,
because a test image usually bakes the repository at a fixed path. Mount it somewhere
else and the run exercises the baked copy: your edit never executes, and the receipt
comes back green with nothing in it saying so. When you find the mount that works,
correct *How to run* in `.veris/NOTES.md`. A fix left only in the PR sends the next
task into the same exit 3.

`--receipt <file>` keeps the receipt — the run's own record of what the sandbox
received — as JSON for the PR. Then read what the twin stored, with
`veris sandbox data get <twin> <table>`, and what it received, with
`veris sandbox trace --tier handler`. Use `--tier fault` instead for an injected
failure.

Both reads have to be of *this* run. Note the newest trace id for that twin before the
run, and read back afterwards with `--service <twin> --since <id>`, because trace ids
are each twin's own sequence. Find your rows by the ids the run produced, not by where
they sit in the listing. A read taken before the changed code ran says nothing about
it.

**Done when the receipt shows at least one request to the twin from that run and
the stored state is what the change promises.** Exit 3 means the flow never reached
the sandbox: fix the wiring, never the call. Exit 4 means the sandbox's ledger could
not be read: run it again, then `veris status`. `--strict` makes the receipt a
stronger claim: that the code reached nothing but the sandbox.

On a repository wired without the proxy, the app reads vendor URLs from the environment
([../veris-reference/direct.md](../veris-reference/direct.md)). There the same gate
reads the trace instead of a receipt. Note the newest trace id before the run, drive
the flow against the wired sandbox, and then
`veris sandbox trace --service <twin> --since <id>` is the run's receipt.

One green proves one path. Before the PR, list every entry point that reaches the
lines you changed: grep the changed symbols for their callers, and the constants
those callers branch on, out to the endpoints, workers and jobs that own them. Say
which of them this run drove. The rest are not covered, so name them under
*limitations and risks*, with what a caller reaching the change that way still gets.

Also search for branches that duplicate the behaviour instead of calling it: the same
response handled inline, selected by a mode or type switch. A grep for your symbol
cannot find those. Drive each one in the green run, or list it. In a large repository
this sweep is worth a subagent where one exists: ask for the entry points, each marked
driven or not driven. The matrix shape is in
[../veris-reference/proof.md](../veris-reference/proof.md), **The route and branch
matrix**. Read that section and **The three layers** above it.

The measurement ledger and Gate 4 belong to `fix`, because a build has no task id and
no ledger. A build still names each measurement in the PR body, with the same four
dispositions.

## The PR

Open a draft the way the repository does. Its body has three sections, in the shape
of [../veris-reference/evidence.md](../veris-reference/evidence.md):

- *What I verified, and how*: each claim, the probe that answered it, the receipt line.
- *What I am assuming rather than verifying*, and why that is acceptable.
- *Limitations and risks*.

Every task premise that measured false is its own line: the premise, the probe, the
answer. Never restate such a premise as fact later in the body.

Paste the sandbox id. Ids stop resolving once the sandbox is deleted. So before
`veris down`, save the rows and trace entries the body cites to
`.veris/evidence/<flow>.json`; `--json` on `veris sandbox data get` and
`veris sandbox trace` writes them. Name that path beside the ids. Whether that file is
committed with the change or only kept on disk is `artifact_policy` in
`.veris/setup.json`, which `setup` set at step 9. Save identifiers, counts and excerpts
only, never credentials. Then run `veris down`.

When a step needs it: [../veris-reference/faults.md](../veris-reference/faults.md)
for faults, credentials and the clock; [../veris-reference/webhooks.md](../veris-reference/webhooks.md)
when the app receives callbacks; [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md)
for what a receipt, an exit code or a vendor-shaped error means. Note anything the
twin got wrong or lacked and tell the engineer at the end. Ask before sending
repository code anywhere new.
