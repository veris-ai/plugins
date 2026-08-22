---
name: discovering-vendor-behavior
description: Measures what an external service actually does before code is designed around it - on a repeat, a lost response, a duplicate, a limit, an expiry. Use when a design depends on how a vendor behaves, and whenever an issue, a comment, a docstring, a teammate, or your own memory asserts what a vendor does or does not support.
---

What Veris can tell you about a vendor, and how to ask.

Veris runs a stateful twin of each service this code calls; a sandbox is one
running deployment of them. The twin answers what the vendor does on a repeat,
a lost response, a duplicate, a limit, an expiry — and can *make those
situations happen*, which the real vendor will not do on demand. Ask before
the design is fixed: each answer is one call now and a production incident
later.

## A sandbox, not a container

`get_environment` → `create_sandbox` → `get_sandbox` until `ready`;
`setting-up-veris` wires an environment when none is. Each service returns
`url` and `control_url`; every `/veris/*` path goes to `control_url`.

Probes are not code under test. Send them straight at `url` with curl or a
short script, using the credentials the manual names — published ones are
readable through `/veris/data`; an OAuth access token must be one the sandbox
issued. The container rule in `integration-testing` protects the shipping
code path only.

## What the twin can tell you

If the task is about a failure — a timeout, a lost response, a retry, a
refusal — that failure, made to happen, is the first probe. A direct call
cannot produce it and the live vendor will not; it is the one thing the twin
answers that documentation does not.

| question | ask |
|---|---|
| What does the failure this task is about look like? | a `faults` row, then the real call through it — shapes below |
| What does the vendor already offer for the thing this change is about? | `GET {control_url}/veris/manual` — the service's own notes, generated from what it declares plus what its authors added. Short, and different for every service — read it whole |
| Is a claim about the vendor's data model true — uniqueness, a required field, an allowed value? | `GET {control_url}/veris/schema` — every table, its fields, and the rule that governs it where the service states one; then one probe. A value the vendor accepts twice is not an identity, and nothing keyed on it can tell two records apart |
| What does the vendor do at the condition the change is about? | a probe — cause the condition and read what came back |
| What did the client actually send? What did the vendor store? | `GET {control_url}/veris/requests` — method, path, headers, body (the query string is not recorded yet); `GET {control_url}/veris/data?entity_type=<name>` |
| What happens after time passes — expiry, retention? | the `clock` row via `PATCH /veris/data`; never backwards |
| What does a rejected credential look like? | arm `auth.mode: enforced` first — in the default mode any well-formed key works, so the probe proves nothing otherwise |
| Which operations does the service publish? | `GET {control_url}/veris/operations`, where a service publishes one; most answer `404` |

Arranging a probe: `GET /veris/data?entity_type=<name>` for an existing id —
never guess one; `POST /veris/data`, in the shapes `/veris/schema` names, for
state the probe needs first; `POST /veris/reset` with `{"profile":"default"}`
for a clean slate between probes. Responses are large: the schema comes
whole and can run to tens of kilobytes, so read it once and keep the tables
the question is about; `/veris/data?entity_type=` returns one entity; keep
from a probe's response only the fields that answer it. Row formats
and the fault contract are in `integration-testing`'s
`reference/state-and-faults.md`.

## Making a failure happen

| the report says | the fault row |
|---|---|
| the response never came back, but the write happened | `"outcome":"hang"` (or an `error` with a 5xx) with `"phase":"after"` |
| we got throttled | `"outcome":"error","error":{"status":429,"code":"<listed-code>","headers":{"Retry-After":"2"}},"remaining":2` |
| the vendor refused | `"outcome":"error","error":{"status":<one the manual lists>,"code":"<listed-code>"},"remaining":1` — an unlisted status answers `422` with the allowed list |
| it was slow enough to time out | `"latency_ms": <n>` |

## Keeping what you measured

A probe's answer is a fact the design can cite and a reviewer can check; an
assumption is neither. Record what was measured where the design decision and
the change description can point at it — `.veris/MEASUREMENTS.md` is one
place — and say under *assuming rather than verifying* what was not.

**NEXT:** `integration-testing` exercises the change through the same failure
made to happen here.
