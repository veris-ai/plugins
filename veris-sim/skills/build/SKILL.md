---
name: build
description: Build a feature against the vendor's twin - measure every vendor claim the task rests on before designing, prove the change through veris-proxy with a receipt, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Build the feature in the request that accompanied this invocation (a GitHub
issue URL or number, or free text). Not done until every gate below is met
and the PR says so.

**The task.** A GitHub reference → `gh issue view <ref> --json title,body,comments`;
quote it. Anything it states about the vendor — what it supports, what a
field means, what a repeat does — is a **claim**, listed as such; vendor
documentation is a claim too.

**A run costs roughly turns × context, and every large output stays resident for
every turn after it.** The expensive mistake is not an extra call; it is pulling a
big response into the thread that then has to carry it. So where subagents exist,
delegate by default anything that reads wide or returns long — a code survey, a
full test-suite run, any output past a screenful — and keep the answer, not the
transcript. Read small things inline: a data census, one projected table, a
filtered trace. No `.veris/run.sh` and no direct-tier `.veris/setup.json` → stop; `setup` runs first. A `setup.json` with `"tier": "direct"` replaces `run.sh`: run the flow directly against the wired sandbox and read the trace where a gate reads the receipt ([direct.md](../setup/reference/direct.md)).
Sandbox lifecycle and every `/veris/*` call: [reference/twin.md](../veris-reference/twin.md).

**The boundary.** Once the claims are listed, name where the vendor
boundary sits in this task. A feature internal to the repository, with no
vendor claim load-bearing: say so, verify by the repository's own test
conventions, and spend the twin on one end-to-end confirmation of the
changed flow instead of the full gate sequence. That one confirmation is a
floor, not a discount: a reduced path that drove nothing through the twin
has not spent less — it has left the change unproven, and the flow the task
names is the one it skipped. Spend the full gates where
the task rests on what the vendor does — the trigger is the boundary,
never self-assessed obviousness.

## Gate 1 — every claim measured before the first source edit

0. `.veris/NOTES.md`, if present — what setup and earlier tasks already
   measured about this environment; do not re-measure it. Append anything
   measured in this task that outlives it.
1. `create_sandbox` (MCP), or `POST ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`
   with `{"ttl_minutes":60}`; then `get_sandbox` until `status` is `ready` —
   one sandbox for this whole task; keep its id and each service's `control_url`.
   A sandbox or proxy session kept alive from an earlier run is a net
   save — reuse it, reading from the ledger what per-run receipt lines
   would have shown.
2. `GET {control_url}/veris/manual` — the service's own notes, short, read
   whole. It is authoritative for exactly these: the statuses and codes a
   fault may inject, the `match` selector keys this service supports, its
   API versions and selector, and its credential and setup notes — the
   selector that makes a repeated write safe is named there or nowhere. It
   is **not** a catalogue of what the service implements, and nothing is —
   read no coverage claim into what it leaves out. A surface the change
   rests on gets one probe, and what a refusal proves is in
   [reference/troubleshooting.md](../veris-reference/troubleshooting.md):
   some settle the question, most do not.
3. The state. A sandbox boots the environment's default state, and the code
   path needs rows in it — the customer an invoice references, the account a
   charge posts to. Take the census first — `GET {control_url}/veris/data`
   with no parameters is every table and its row count in one small
   response — then read the shape of only the tables that matter:
   ```sh
   curl --fail-with-body -sS "$CONTROL_URL/veris/schema" |
     jq -e --arg table "$TABLE" \
       '.properties[$table] // error("unknown table: \($table)")'
   ```
   A whole schema is far larger than any one task needs; project it.
   `GET {control_url}/veris/data?entity_type=<table>` then shows what is
   already there; seed what is missing, in the shapes the schema names:
   ```http
   POST {control_url}/veris/data
   {"data":{"<entity>":[{"<primary-key>":"test-owned-id","<field>":"value"}]}}
   ```
   File bytes are not rows: seed the rows first, then post the files
   through `/veris/files` ([reference/state.md](../veris-reference/state.md)).
   Ids come from the sandbox, never guessed and never carried from another
   sandbox. A call that fails because a row was absent has
   measured nothing. The state dies with its sandbox — resetting it, or
   keeping it: [reference/state.md](../veris-reference/state.md).
4. For each claim: one probe against `url`, or one schema read, that answers
   it — the questions and their asks are in [reference/twin.md](../veris-reference/twin.md).
   Record the call and the answer; a measurement that contradicts the task
   is the finding, not an error.
5. If the feature is about a failure — a lost response, a limit, a refusal —
   make it happen and drive the current code through it before designing:
   [reference/faults.md](../veris-reference/faults.md).

Write the source only after every claim has an answer.
## Gate 2 — the identity the design rests on

Before the change keys, looks up, or dedupes on any field, read that field's
rule in `GET {control_url}/veris/schema` (the table's description). A field the vendor accepts
twice for distinct records is not an identity; a design anchored on it
collapses two real records or misses a repeat. Name the field the design
rests on, and why it is one, in the PR.

The gate binds on any identity, dedup key or external reference the design
sends across the vendor boundary, however the code got it — computed,
copied from an input, reused from an id the caller already carries. Copying
does not discharge it: what the value leaves out has no row in the schema
to read, and the collision lives there. Prove it against the twin. Vary
each component of the identity independently — including an input that
omits one — drive them through the same path, and count the rows the vendor
stored: distinct inputs must have left distinct records. Fewer is the
design's own defect, caught before it ships. The identity, what you varied
and the counts go in the PR beside the field.

## Implement

As the repository does it: its test conventions, its coverage gate, nothing
pointed at a sandbox, no vendor call changed to make a test pass. The
repository's full test gate runs once: backgrounded, no self-imposed
timeout, polled to completion, its result read before the PR is written.
Never kill a running suite to relaunch it; never report a result that was
not read.

## Gate 3 — the change through veris-proxy, with a receipt

Run the changed flow from the boundary the task names — endpoint, worker,
handler — through `.veris/run.sh` with `VERIS_SANDBOX_ID` set to the gate-1
sandbox ([reference/proxy.md](../veris-reference/proxy.md)), against the
conditions measured there, and read back what the vendor
stored (`GET {control_url}/veris/data?entity_type=<table>`, and the trace at
the tier the evidence is on — `tier=handler` for ordinary traffic,
`tier=fault` for an injected one). **Not done until the receipt
shows at least one request to the service from that run.** A green earned
by changing the caller's call proves the caller changed.

One green proves one path. Before the PR, list every entry point that
reaches the lines you changed — grep the changed symbols for their callers,
and the constants those callers branch on, out to the endpoints, workers,
handlers and jobs that own them — and say which of them this run actually
drove. The ones it did not are not covered: they belong under *limitations
and risks*, named, with what a caller reaching the change that way would
still get. A shared helper reached three ways and driven once is a change
proved one third of the way. Callers are not the whole list: a branch that
duplicates the behavior rather than calling it — the same response handled,
the same request built inline, selected by a mode or type switch — cannot
appear in a grep for the symbol you changed. Search for those siblings,
name each one you found, and either drive it in the green run or put it
under *limitations and risks* with why it is out of scope. An unexercised
sibling reported as covered fails this gate. In a repository large enough
that this sweep spans many files, it is worth a subagent where one is
available: ask for the entry points, each marked driven or not-driven.

## The PR

Open a draft as the repository does. Its body has three sections, in the
shape of [reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* — each claim, the probe, the receipt line; *what I am assuming
rather than verifying*, and why that is acceptable; *limitations and risks*.
Every task premise measured false is its own line in the body — the
premise, the probe, the answer — and is never restated as fact after that
measurement, in prose, code, or a name. Paste the sandbox id. Then `delete_sandbox` (or `DELETE …/sandboxes/<id>`).

When a step needs it: [state.md](../veris-reference/state.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (an SDK refusing the proxy's certificate),
[troubleshooting.md](../veris-reference/troubleshooting.md). Note anything the
sandbox got wrong or lacked and give it to the engineer at the end. Ask
before sending repository code anywhere new. Never promote a sandbox.
