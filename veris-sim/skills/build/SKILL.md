---
name: build
description: Build a feature against the vendor's twin - measure every vendor claim the task rests on before designing, prove the change through veris-proxy with a receipt, write the PR with what was verified and assumed. Takes an issue link or a prompt.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Build the feature in the request that accompanied this invocation (a GitHub
issue URL or number, or free text). Not done until every gate below is met
and the PR says so.

**The task.** A GitHub reference → `gh issue view <ref> --json title,body,comments`;
quote it. Anything it states about the vendor — what it supports, what a
field means, what a repeat does — is a **claim**, listed as such; vendor
documentation is a claim too. No `.veris/run.sh` → stop; `setup` runs first.
Sandbox lifecycle and every `/veris/*` call: [reference/twin.md](../veris-reference/twin.md).

## Gate 1 — every claim measured before the first source edit

1. `create_sandbox` (MCP), or `POST $VERIS_API_BASE/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`
   with `{"ttl_minutes":60}`; then `get_sandbox` until `status` is `ready` —
   one sandbox for this whole task; keep its id and each service's `control_url`.
2. `GET {control_url}/veris/manual` — the service's own notes, read whole once. It
   names what the vendor already offers for this feature and the selector
   that makes a repeated write safe, or that none exists.
3. For each claim: one probe against `url`, or one schema read, that answers
   it — the questions and their asks are in [reference/twin.md](../veris-reference/twin.md).
   Record the call and the answer; a measurement that contradicts the task
   is the finding, not an error.
4. If the feature is about a failure — a lost response, a limit, a refusal —
   make it happen and drive the current code through it before designing:
   [reference/faults.md](../veris-reference/faults.md).

Write the source only after every claim has an answer.

## Gate 2 — the identity the design rests on

Before the change keys, looks up, or dedupes on any field, read that field's
rule in `GET {control_url}/veris/schema` (the table's description). A field the vendor accepts
twice for distinct records is not an identity; a design anchored on it
collapses two real records or misses a repeat. Name the field the design
rests on, and why it is one, in the PR.

## Implement

As the repository does it: its test conventions, its coverage gate, nothing
pointed at a sandbox, no vendor call changed to make a test pass.

## Gate 3 — the change through veris-proxy, with a receipt

Run the changed flow from the boundary the task names — endpoint, worker,
handler — through `.veris/run.sh` ([reference/proxy.md](../veris-reference/proxy.md)),
against the conditions measured in gate 1, and read back what the vendor
stored (`GET {control_url}/veris/data?entity_type=<table>`,
`GET {control_url}/veris/requests`). **Not done until the receipt
shows at least one request to the service from that run.** A green earned
by changing the caller's call proves the caller changed.

## The PR

Open a draft as the repository does. Its body has three sections, in the
shape of [reference/evidence.md](../veris-reference/evidence.md): *what I verified,
and how* — each claim, the probe, the receipt line; *what I am assuming
rather than verifying*, and why that is acceptable; *limitations and risks*.
Paste the sandbox id. Then `delete_sandbox` (or `DELETE …/sandboxes/<id>`).

When a step needs it: [worlds.md](../veris-reference/worlds.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (an SDK refusing the proxy's certificate),
[troubleshooting.md](../veris-reference/troubleshooting.md). Note anything the
sandbox got wrong or lacked and give it to the engineer at the end. Ask
before sending repository code anywhere new. Never promote a sandbox.
