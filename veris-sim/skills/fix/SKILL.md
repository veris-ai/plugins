---
name: fix
description: Fix a defect against the vendor's twin - reproduce the failure the issue describes through the repository's own code before designing, prove it closed through veris-proxy with a receipt, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Fix the defect in the request that accompanied this invocation (a GitHub
issue URL or number, or free text). Not done until every gate below is met
and the PR says so.

**The task.** A GitHub reference → `gh issue view <ref> --json title,body,comments`;
quote it. Name the failure in one sentence: what the vendor did, what the
code did next. Anything the issue states about the vendor — what it
supports, why it fails, what a field means — is a **claim**, the diagnosis
included. No `.veris/run.sh` and no direct-tier `.veris/setup.json` → stop; `setup` runs first. A `setup.json` with `"tier": "direct"` replaces `run.sh`: run the flow directly against the wired sandbox and read the trace where a gate reads the receipt ([direct.md](../setup/reference/direct.md)). Sandbox
lifecycle and every `/veris/*` call: [reference/twin.md](../veris-reference/twin.md).

**The diagnosis.** Before any sandbox: read the code path the issue names
and enumerate every distinct defect that could produce the symptom — the
vendor's failures and the repository's own (state lost between requests, a
queue, a cache, a race), which no twin can represent. The manual's fault
catalog is one hypothesis source, never the selector: the twin confirms a
diagnosis chosen from code evidence, it does not choose it. Bulk
reconnaissance — a wide code survey, a large data census — belongs in a
delegated subagent when one is available, so this session's context stays
small.

**The boundary.** Name where the vendor boundary sits in this task. A
defect internal to the repository, with no vendor claim load-bearing: say
so, verify by the repository's own test conventions, and spend the twin on
one end-to-end confirmation of the changed flow instead of the full gate
sequence. Spend the full gates where the task rests on what the vendor
does — the trigger is the boundary, never self-assessed obviousness.

## Gate 1 — the failure reproduced before the first source edit

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
   **before any other call to the twin, the schema included**. It says what
   the vendor offers for exactly this — a retry selector, a limit, a rule —
   or that nothing does; that is the first claim to check. What the manual
   excludes, the twin will refuse (`feature_not_supported`): one manual read
   answers in seconds what a chain of probes answers one refusal at a time,
   and an excluded surface is a finding for the engineer, not a wall to
   probe around. The manual and the schema together are the complete
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
   sandbox. A call that fails because a row was absent is not the
   failure the issue describes. The world dies with its sandbox — resetting one, or
   keeping one: [reference/worlds.md](../veris-reference/worlds.md).
4. Make the failure happen. The vendor will not produce it on demand. A
   vendor-side defect: arm a `faults` row in the shape
   [reference/faults.md](../veris-reference/faults.md) gives for what the issue
   reports. A repository-side defect no fault can produce: reproduce it
   through the application's own state — and when the twin cannot
   represent it at all, that report is the Gate-1 outcome, not a reason to
   switch diagnoses. Either way, drive the **repository's own code path** — the endpoint,
   worker or handler the issue names, unchanged — through it under
   `.veris/run.sh` with `VERIS_SANDBOX_ID` set to this sandbox
   ([reference/proxy.md](../veris-reference/proxy.md)).
5. Read the ledger: `GET {control_url}/veris/data?entity_type=<table>` and
   `GET {control_url}/veris/requests`. Not done with this gate until they show the
   outcome the issue describes — the duplicate row, the lost write, the
   wrong state — with ids and counts you can quote.

The order is the evidence. The red run is observed against the
repository's unmodified code, before the first source edit; a red produced
afterward by stashing the fix satisfies nothing — it can no longer
challenge the diagnosis. The PR presents the red and green runs in the
order they actually happened.

If the failure will not reproduce, that is the finding: report what the
twin did instead, with the trace, and stop before changing code.
## Gate 2 — the identity the fix rests on

Before the fix keys, looks up, or dedupes on any field, read that field's
rule in `GET {control_url}/veris/schema` (the table's description). A field the vendor accepts
twice for distinct records is not an identity; a fix anchored on it trades
one failure for another. Name the field the fix rests on, and why it is
one, in the PR.

A key the fix *computes* — parts joined, a value normalized, truncated or
hashed — has no row in the schema to read: the collision lives in the
derivation, not in the vendor's fields, and the schema read cannot clear
it. Prove the derivation instead. Construct two inputs the code must keep
apart that it maps to the same key — parts that regroup across the join
(`a`+`bc` against `ab`+`c`), a pair the normalizer folds together, two
values that agree up to the truncation — drive both through the same path,
and count the rows the vendor stored. Two rows is the answer; one is the
fix's own defect, caught before it ships. The derivation, the pair and the
count go in the PR beside the field. Questions and their asks:
[reference/twin.md](../veris-reference/twin.md).

## Implement

As the repository does it: its test conventions, its coverage gate, nothing
pointed at a sandbox, no vendor call changed to make a test pass. The
repository's full test gate runs once: backgrounded, no self-imposed
timeout, polled to completion, its result read before the PR is written.
Never kill a running suite to relaunch it; never report a result that was
not read.

## Gate 3 — the same failure, closed, with a receipt

Re-arm the same fault; drive the same code path through `.veris/run.sh`
(same `VERIS_SANDBOX_ID`); read the ledger again. **Not done until the receipt shows at least one
request to the service from that run and the ledger shows the outcome the
fix promises** — one row where there were two, the write recovered, the
state right. Red before, green after, same flow: that is the proof.

One green proves one path. Before the PR, list every entry point that
reaches the lines you changed — grep the changed symbols for their callers,
and the constants those callers branch on, out to the endpoints, workers,
handlers and jobs that own them — and say which of them this run actually
drove. The ones it did not are not covered: they belong under *limitations
and risks*, named, with what a caller reaching the fix that way would still
get. A shared helper reached three ways and driven once is a fix for one
third of the defect.

## The PR

Open a draft as the repository does. Its body has three sections, in the
shape of [reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* — the fault armed, the before ledger, the after ledger, the receipt
line; *what I am assuming rather than verifying*, and why that is
acceptable; *limitations and risks* — including what a caller could still do
wrong. Every task premise measured false is its own line in the body — the
premise, the probe, the answer — and is never restated as fact after that
measurement, in prose, code, or a name. Paste the sandbox id. Then `delete_sandbox` (or `DELETE …/sandboxes/<id>`).

When a step needs it: [worlds.md](../veris-reference/worlds.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (an SDK refusing the proxy's certificate),
[troubleshooting.md](../veris-reference/troubleshooting.md). Note anything the
sandbox got wrong or lacked and give it to the engineer at the end. Ask
before sending repository code anywhere new. Never promote a sandbox.
