---
name: integration-testing
description: Runs the application's own code against a Veris environment through veris-proxy - unmodified, with a receipt of what the sandbox received. Use when a change to code that calls an external service needs exercising - a feature, a fix, a migration, a regression suite - when a reported integration behaviour needs reproducing, and before a change is called done.
---

What a run against the twin gives you, and how to read it.

Veris runs a stateful twin of each service this code calls; a sandbox is one
running deployment of them. A run puts the application's own code in front of
the twin — unmodified: its production hostnames, credentials and client stack
— with `veris-proxy` rerouting its outbound HTTP(S) from outside the process,
and ends with a **receipt** of what the sandbox received.
`discovering-vendor-behavior` asks the twin about the vendor; this skill asks
it about the application.

No `.veris/run.sh` yet → `setting-up-veris`. A design resting on a claim about
the vendor you have not seen it make → `discovering-vendor-behavior`.

## The run

`.veris/run.sh` carries the command: flags before `--` pass through, a command
after `--` replaces its default. Without it:

```bash
veris-proxy run --environment "$VERIS_ENVIRONMENT_ID" --image <test-image> \
  -v "$PWD:/work" -w /work -- <test command>
```

The run deploys a fresh sandbox of the environment, runs the command against
it, prints the receipt, and deletes the sandbox. It logs
`sandbox ready sandbox_id=<id>`; `get_sandbox` with that id returns each
service's `control_url`, so state, faults and read-back are available for as
long as the run lives.

| flag | what it does |
|---|---|
| `--environment <id>` | a sandbox per run, deleted after; `--ttl-minutes` bounds one that outlives a crashed run |
| `--require-service <name>[:count]`, `--require-host <host>[:count]` | makes a specific service or host, or call count, the verdict; optional |
| `--route <service>=<host>[/prefix]` | routes a service at a hostname the embedded table does not know — an application that calls the vendor at a regional or custom endpoint |
| `--cap-add <CAP>` | the workload runs with every capability dropped; an entrypoint that switches users (`su`, `gosu`, `service`) needs `SETUID` and `SETGID`, or build the image to run as that user. `ALL` and `SYS_ADMIN` are refused |
| `--strict` | a request to an unmapped host is answered with a `502` naming the host instead of reaching the real internet — the claim "the code reached nothing but the sandbox" |
| `--patch-bundled-cas` | for stripe (Python or Ruby), older botocore, httplib2 — SDKs that refuse the proxy's certificate quietly; [reference/trust.md](reference/trust.md) |
| `--expose <port>` | a public URL for the application to receive callbacks; [reference/webhooks.md](reference/webhooks.md) |
| `--keep-proxy` | leaves the proxy container up for inspection |

Exit codes: the command's own; `3` — the run never proved its traffic (empty
receipt, an unmet `--require-*`, or every TLS handshake to a mapped host
rejected, with a diagnostic naming the next action); `4` — indeterminate, a
failure.

## What a run can include

All through the run's sandbox at `control_url`; the contract for each is in
[reference/state-and-faults.md](reference/state-and-faults.md).

| need | control |
|---|---|
| the state a case needs | `POST /veris/data`, in the shapes `/veris/schema` names; ids from `GET /veris/data?entity_type=<name>`, never guessed |
| a failure the vendor will not produce on demand | a `faults` row — the response lost after the write, a throttle, a refusal, latency |
| time passing | the `clock` row via `PATCH /veris/data` |
| what the application actually sent, and what the vendor stored afterwards | `GET /veris/requests`; `GET /veris/data?entity_type=<name>` |
| a rejected credential | `auth.mode: enforced` first — in the default mode any well-formed key works |

One session, many passes: start with `.veris/run.sh -- sleep infinity &`, then
`docker exec "$(docker ps -q -f name=veris-workload-)" bash -lc '<one pass>'`
as often as needed; `kill %1` ends the run and prints the receipt for the whole
session. Several steps in one run chain through the image's shell:
`.veris/run.sh -- bash -lc 'python seed.py && pytest tests/integration -x'`.

## What a green proves

A green and a receipt prove the change only together, and only from the same
run:

- the receipt names the service the tests were meant to reach — it counts
  every completed request to a mapped vendor host, the suite's own setup
  traffic included; the paths in `/veris/requests` say whose it was;
- the run executed the changed code on its way to the vendor: a flow from the
  boundary the task names — the endpoint, worker, job or handler, not the SDK
  call inside it — with the call the report describes, unchanged. A green
  earned by changing the caller's call proves the caller changed;
- the same flow red before the change and green after it is the strongest
  form;
- nothing in the repository or its environment was pointed at a sandbox.

[reference/evidence.md](reference/evidence.md) is a shape for the change
description's verification section: what was verified and how, what is
assumed instead, limitations.

## Reference

- [reference/state-and-faults.md](reference/state-and-faults.md) — every
  `/veris/*` control: state, seeding, credentials, fault rows, the clock,
  read-back.
- [reference/troubleshooting.md](reference/troubleshooting.md) — what the
  receipt, the trace, an exit code and a vendor-shaped error each mean.
- [reference/trust.md](reference/trust.md) — SDKs that bundle their own CA,
  a sidecar the run did not start, the two-retry loop.
- [reference/worlds.md](reference/worlds.md) — isolation, reset, promote,
  snapshots.
- [reference/webhooks.md](reference/webhooks.md) — `--expose`,
  `--require-callback`, delivery without inbound HTTP.
- [reference/evidence.md](reference/evidence.md) — a shape for the
  verification section.

## Reporting back

Keep a record of anything about the sandbox that confused or blocked you —
a gap in its manual, behaviour that contradicted it, a response that differs
from the real vendor, a failure you could not attribute — with the request and
response. Give it to the user at the end; it goes back to Veris, and it is how
the twins improve.

## Ask before

Installing veris-proxy, registering the MCP server, or sending repository code
to a new external destination. Sandbox lifecycle operations are routine.
