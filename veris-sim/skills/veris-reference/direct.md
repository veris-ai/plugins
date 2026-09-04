# Direct tier: when the environment variables are the shipped path

The proxy exists for code that must not change: production hostnames stay in the
code, and rerouting happens below the process. An application built the other way,
every vendor base URL read from the environment variable the platform names for that
twin (its env hint), the same variables production sets, needs no reroute. Pointing
those variables at a sandbox exercises exactly the code path that ships. That, and
only that, is what the direct tier is for.

## The gate

Before using it, verify in the code, not from the engineer's answer, that every
vendor call on the tested path builds its URL from those variables. One hardcoded
vendor hostname, in the app or inside an SDK it calls, means the container tier. The
host tier is not a fallback either. Greenfield and agent-built applications usually
pass this gate; retrofits usually do not.

SDK caveat, measured: an SDK whose base-URL setting keeps the vendor's host and
replaces only the path cannot reach a sandbox URL, which carries a path prefix.
Google's client libraries' `rootUrl` is such a setting. Raw HTTP clients and SDKs
that accept a full base URL work. When the SDK cannot, that is a container-tier
signal, not a reason to fork the app's HTTP layer.

## Wiring

1. `veris up`.
2. `veris sandbox exports` prints one `export NAME=url` line per twin to stdout and
   nothing else there; a twin with no env hint is skipped with a `!` line on stderr.
   Set those variables wherever the app's environment actually comes from:
   `eval "$(veris sandbox exports)"`, an env file (`--format dotenv` prints
   `KEY=value` lines), or a platform's secrets pane. Some panes accept only a human
   (Replit's does); then name each variable and value, wait for the engineer to
   confirm, and never print other secrets while doing it. For a vendor MCP server,
   use the twin's URL with the vendor's MCP path.
3. Credentials stay vendor-shaped: the sandbox publishes working ones (`veris sandbox
   data get <twin>` per the manual), or the app's own connect flow mints them against
   the identity twin.

## The trust anchor

There is no proxy receipt. The twin's trace replaces it: after the smallest real call
the app can make, `veris sandbox trace` must show that call. An empty trace with a
green smoke means the traffic went to the real vendor. Every later "did it work"
question has the same two answers the proxy tier has: the trace, what was sent, and
`veris sandbox data get`, what the vendor stored.

## Sandbox lifetime and rotation

A direct-tier sandbox is bound to a running application, so it lives until rotated.
Give it a generous but finite TTL: `veris up --ttl <minutes>`, or `ttl_minutes` in
`.veris/twin.yaml`. When it expires or its state must reset: `veris up` again,
re-set the variables from `veris sandbox exports`, restart the app. A new
sandbox boots the environment's default state; rows and files that were never
promoted are gone, so load them again or promote once (`setup`, files step). Make
token bootstrap part of application startup so rotation needs nothing else; a cached
token from a dead sandbox is the first thing to fail after rotation.

## What the direct tier is not

It does not weaken the promotion rule (never promote a task sandbox), the identity
rules in [twin.md](twin.md), or the fault discipline in [faults.md](faults.md). And
`build` and `fix` work unchanged on it: wherever a gate says "through `veris run`, a
receipt per run", the direct-tier equivalent is "against the wired sandbox, trace per
run": read `veris sandbox trace --since <last id>` before and after the run and
attribute by the delta, since a shared sandbox's trace is not per-process the way a
receipt is. A suite that needs per-test isolation isolates by data, own root resources
per test, rather than by sandbox.
