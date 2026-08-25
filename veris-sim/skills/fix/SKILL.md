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

## Gate 1 — the failure reproduced before the first source edit

1. `create_sandbox` (MCP), or `POST $VERIS_API_BASE/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`
   with `{"ttl_minutes":60}`; then `get_sandbox` until `status` is `ready` —
   one sandbox for this whole task; keep its id and each service's `control_url`.
2. `GET {control_url}/veris/manual` — the service's own notes, read whole once. It
   says what the vendor offers for exactly this — a retry selector, a limit,
   a rule — or that nothing does; that is the first claim to check.
3. Make the failure happen. The vendor will not produce it on demand; the
   twin will: arm a `faults` row in the shape
   [reference/faults.md](../veris-reference/faults.md) gives for what the issue
   reports, then drive the **repository's own code path** — the endpoint,
   worker or handler the issue names, unchanged — through it under
   `.veris/run.sh` with `VERIS_SANDBOX_ID` set to this sandbox
   ([reference/proxy.md](../veris-reference/proxy.md)).
4. Read the ledger: `GET {control_url}/veris/data?entity_type=<table>` and
   `GET {control_url}/veris/requests`. Not done with this gate until they show the
   outcome the issue describes — the duplicate row, the lost write, the
   wrong state — with ids and counts you can quote.

If the failure will not reproduce, that is the finding: report what the
twin did instead, with the trace, and stop before changing code.

## Gate 2 — the identity the fix rests on

Before the fix keys, looks up, or dedupes on any field, read that field's
rule in `GET {control_url}/veris/schema` (the table's description). A field the vendor accepts
twice for distinct records is not an identity; a fix anchored on it trades
one failure for another. Name the field the fix rests on, and why it is
one, in the PR. Questions and their asks: [reference/twin.md](../veris-reference/twin.md).

## Implement

As the repository does it: its test conventions, its coverage gate, nothing
pointed at a sandbox, no vendor call changed to make a test pass.

## Gate 3 — the same failure, closed, with a receipt

Re-arm the same fault; drive the same code path through `.veris/run.sh`
(same `VERIS_SANDBOX_ID`); read the ledger again. **Not done until the receipt shows at least one
request to the service from that run and the ledger shows the outcome the
fix promises** — one row where there were two, the write recovered, the
state right. Red before, green after, same flow: that is the proof.

## The PR

Open a draft as the repository does. Its body has three sections, in the
shape of [reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* — the fault armed, the before ledger, the after ledger, the receipt
line; *what I am assuming rather than verifying*, and why that is
acceptable; *limitations and risks* — including what a caller could still do
wrong. Paste the sandbox id. Then `delete_sandbox` (or `DELETE …/sandboxes/<id>`).

When a step needs it: [worlds.md](../veris-reference/worlds.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (an SDK refusing the proxy's certificate),
[troubleshooting.md](../veris-reference/troubleshooting.md). Note anything the
sandbox got wrong or lacked and give it to the engineer at the end. Ask
before sending repository code anywhere new. Never promote a sandbox.
