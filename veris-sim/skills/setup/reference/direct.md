# Direct tier: when the env vars ARE the shipped path

The proxy exists to test code that must not change: production hostnames
stay hardcoded, and rerouting happens below the process. An application
built the other way — every vendor base URL read from the environment
variable the platform names for that service (its `env_hint`), the same
variables production will set — needs no reroute. Pointing those variables
at a sandbox exercises exactly the code path that ships. That, and only
that, is what `--direct` is for.

## The gate

Before accepting `--direct`, verify in the code — not from the engineer's
answer — that every vendor call on the tested path builds its URL from the
`env_hint` variables. One hardcoded vendor hostname (in the app or inside
an SDK it calls) means the container tier; the host tier is not a fallback
here either. Greenfield applications and agent-built applications usually
pass this gate; retrofits usually do not.

SDK caveat, measured: an SDK whose base-URL setting keeps the vendor's host
and replaces only the path cannot reach a path-prefixed sandbox URL
(`/s/{sandbox}/{service}/…`). googleapis' `rootUrl` is such a setting. Raw
HTTP clients and SDKs that accept a full base URL work; when the SDK cannot,
that is a container-tier signal, not a reason to fork the app's HTTP layer.

## Wiring

1. `create_sandbox` (MCP) or
   `POST $VERIS_API_BASE/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`;
   poll to `ready`.
2. `get_sandbox` lists each service's `env_hint` and `url`. Set each
   variable wherever the application's environment actually comes from — a
   platform Secrets pane, an env file, an export. Some panes accept only a
   human (Replit's Secrets pane is one, measured): name every variable and
   its value, wait for the engineer to confirm, and never print other
   secrets while doing it.
3. Credentials stay vendor-shaped: the sandbox publishes working ones —
   `GET {control_url}/veris/data` per the service manual — or the
   application's own connect flow mints them against the identity service.

## The trust anchor

There is no proxy receipt. The twin's request trace replaces it: after the
smallest real call the application can make,
`GET {control_url}/veris/requests` must show that call. An empty trace with
a green smoke means the traffic went to the real vendor. Every later "did
it work" question has the same two answers the proxy tier has — the trace
(what was sent) and `/veris/data` (what the vendor stored).

## Sandbox lifetime and rotation

A container-tier sandbox lives for one run. A direct-tier sandbox is bound
to a running application, so it lives until rotated. Set `ttl_minutes`
generously but finitely; when the sandbox expires or its data must reset,
the rotation is: create a new sandbox, re-set the `env_hint` variables,
restart the application. Make token bootstrap part of application startup
so rotation needs nothing else — a cached token from a dead sandbox is the
first thing to fail after rotation.

## What direct mode is not

It does not weaken the promotion rule (never promote a task sandbox), the
identity rules in `twin.md`, or the fault discipline in `faults.md` — those
are transport-independent. And it is not a way to run `build`/`fix`/`test`
without their gates: the commands work unchanged on a direct-tier setup;
wherever a gate says "through `.veris/run.sh`, receipt per run," the
direct-tier equivalent is "against the wired sandbox, trace per run" —
save `GET {control_url}/veris/requests` before and after the run and
attribute by the delta, since a shared sandbox's trace is not per-process
the way a receipt is. A suite that needs per-test isolation on the direct
tier isolates by data (own root resources) rather than by sandbox.
