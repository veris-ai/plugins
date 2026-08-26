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
documentation is a claim too. Bulk reconnaissance — a wide code survey, a
large data census — belongs in a delegated subagent when one is available,
so this session's context stays small. No `.veris/run.sh` and no direct-tier `.veris/setup.json` → stop; `setup` runs first. A `setup.json` with `"tier": "direct"` replaces `run.sh`: run the flow directly against the wired sandbox and read the trace where a gate reads the receipt ([direct.md](../setup/reference/direct.md)).
Sandbox lifecycle and every `/veris/*` call: [reference/twin.md](../veris-reference/twin.md).

**The boundary.** Once the claims are listed, name where the vendor
boundary sits in this task. A feature internal to the repository, with no
vendor claim load-bearing: say so, verify by the repository's own test
conventions, and spend the twin on one end-to-end confirmation of the
changed flow instead of the full gate sequence. Spend the full gates where
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
2. `GET {control_url}/veris/manual` — the service's own notes, read whole,
   **before any other call to the twin, the schema included**. It names
   what the vendor already offers for this feature and the selector that
   makes a repeated write safe, or that none exists. What the manual
   excludes, the twin will refuse (`feature_not_supported`): one manual
   read answers in seconds what a chain of probes answers one refusal at a
   time, and an excluded surface is a finding for the engineer, not a wall
   to probe around. The manual and the schema together are the complete
   statement of what the twin models: a capability absent from both is
   absent from the twin — record it as unsupported, cover that side by the
   repository's own test conventions, report the gap, and never probe
   endpoint by endpoint to rediscover an absence.
3. The world. A sandbox boots the environment's default world, and the code
   path needs rows in it — the customer an invoice references, the account a
   charge posts to. `GET {control_url}/veris/data?entity_type=<table>` shows what
   is already there; seed what is missing, in the shapes `GET {control_url}/veris/schema`
   names:
   ```http
   POST {control_url}/veris/data
   {"data":{"<entity>":[{"<primary-key>":"test-owned-id","<field>":"value"}]}}
   ```
   Ids come from the world, never guessed and never carried from another
   sandbox. A call that fails because a row was absent has
   measured nothing. The world dies with its sandbox — resetting one, or
   keeping one: [reference/worlds.md](../veris-reference/worlds.md).
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

A key the design *computes* — parts joined, a value normalized, truncated
or hashed — has no row in the schema to read: the collision lives in the
derivation, not in the vendor's fields, and the schema read cannot clear
it. Prove the derivation instead. Construct two inputs the code must keep
apart that it maps to the same key — parts that regroup across the join
(`a`+`bc` against `ab`+`c`), a pair the normalizer folds together, two
values that agree up to the truncation — drive both through the same path,
and count the rows the vendor stored. Two rows is the answer; one is the
design's own defect, caught before it ships. The derivation, the pair and
the count go in the PR beside the field.

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
stored (`GET {control_url}/veris/data?entity_type=<table>`,
`GET {control_url}/veris/requests`). **Not done until the receipt
shows at least one request to the service from that run.** A green earned
by changing the caller's call proves the caller changed.

One green proves one path. Before the PR, list every entry point that
reaches the lines you changed — grep the changed symbols for their callers,
and the constants those callers branch on, out to the endpoints, workers,
handlers and jobs that own them — and say which of them this run actually
drove. The ones it did not are not covered: they belong under *limitations
and risks*, named, with what a caller reaching the change that way would
still get. A shared helper reached three ways and driven once is a change
proved one third of the way.

## The PR

Open a draft as the repository does. Its body has three sections, in the
shape of [reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* — each claim, the probe, the receipt line; *what I am assuming
rather than verifying*, and why that is acceptable; *limitations and risks*.
Every task premise measured false is its own line in the body — the
premise, the probe, the answer — and is never restated as fact after that
measurement, in prose, code, or a name. Paste the sandbox id. Then `delete_sandbox` (or `DELETE …/sandboxes/<id>`).

When a step needs it: [worlds.md](../veris-reference/worlds.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (an SDK refusing the proxy's certificate),
[troubleshooting.md](../veris-reference/troubleshooting.md). Note anything the
sandbox got wrong or lacked and give it to the engineer at the end. Ask
before sending repository code anywhere new. Never promote a sandbox.
