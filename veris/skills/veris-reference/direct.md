# Direct tier: when the environment variables are the shipped path

The proxy exists for code that must not change: production hostnames stay in the
code, and rerouting happens below the process. An application built the other way,
every vendor base URL read from the environment variable the platform names for that
twin (its env hint), the same variables production sets, needs no reroute. Pointing
those variables at a sandbox exercises exactly the code path that ships. That is the
first reason to use this tier.

The second is not a preference at all. Some twins have no vendor hostname, and those
are the data planes; `veris services` shows them with `— (not intercepted)` where the
hosts would be. A data plane cannot be intercepted, because there is nothing to
intercept: yente answers on an instance you run yourself, and Postgres speaks a wire
protocol the proxy does not.

That same `—` also marks a vendor twin the control plane serves no hostname for yet.
Such a twin is not a data plane and belongs on the proxy tier, and `veris doctor`'s
vendor-hostnames line tells the two apart.

A data-plane twin is published only as an env hint. In the container tier `veris run`
hands that hint to the workload for you; [run.md](run.md), *What the run hands the
workload*, says how. Here you set the hint yourself, and when there is no run to hand
it over that is the only way to reach a data plane. A mixed application can take the
proxy for its vendor twins and this tier for those.

## The gate

Before using it, verify in the code, not from the engineer's answer, that every
vendor call on the tested path builds its URL from those variables. One hardcoded
vendor hostname, in the app or inside an SDK it calls, means the container tier. The
host tier is not a fallback either. Greenfield and agent-built applications usually
pass this gate; retrofits usually do not.

Then the second half of the gate, which the first half hides. The risk is per base,
not per call. Enumerate every base **each provider registers**, not only the bases the
smoke exercises. Compare that list against the hint variables `veris services` names;
that command needs no sandbox. Once wiring step 2 has run, `veris sandbox exports`
gives the same list, valued at the sandbox.

A base no twin publishes a hint for stays pointed at the real vendor for the whole run,
and nothing in this tier will stop it: there is no `--strict` here, no proxy, and no
receipt to notice. Real credentials in the process, plus one unwired base, is this
tier's one genuinely dangerous property. This was measured on a repository that passes
the first half cleanly: four registered bases had no published hint, and one of them
named a host its twin does cover. Either no tested path reaches such a base, or this is
the wrong tier. Tell the engineer which bases you found unwired, whichever way it
goes.

SDK caveat, measured: an SDK whose base-URL setting keeps the vendor's host and
replaces only the path cannot reach a sandbox URL, which carries a path prefix.
Google's client libraries' `rootUrl` is such a setting. Raw HTTP clients and SDKs
that accept a full base URL work. When the SDK cannot, that is a container-tier
signal, not a reason to fork the app's HTTP layer.

## Wiring

1. A folder with no `.veris/twin.yaml` has nothing for `veris up` to bring up, which
   is exactly the state of the fresh dev box this tier is for. Make one first:
   `veris env create <name> --from <environment id> --ttl <minutes> --default`. With no
   environment on the server to adopt, name the twins instead: `--services <names>` in
   place of `--from`, as `setup` step 4 does. No proxy flags belong here, and no
   `--command`: a flag left out is left out of the file, and this tier never runs one.
2. `veris up`.
3. `veris sandbox exports` prints one `export NAME=url` line per twin to stdout and
   nothing else there; a twin with no env hint is skipped with a `!` line on stderr,
   though in practice every twin in the catalog carries one today. Set those variables
   wherever the app's environment actually comes from:
   `eval "$(veris sandbox exports)"`, an env file (`--format dotenv` prints
   `KEY=value` lines), or a platform's secrets pane. Some panes take input only from a
   human, and Replit's is one. There, name each variable and its value, wait for the
   engineer to confirm, and never print other secrets while doing it. For a vendor MCP
   server, use the twin's URL with the vendor's MCP path.
4. Credentials stay vendor-shaped. Read `veris sandbox data get <twin> auth` before
   hunting for a published key: a `permissive` twin accepts any well-formed credential,
   so a throwaway value in whatever file or variable the app already reads is enough,
   and that is how twins boot. Only an `enforced` twin needs the published one (`veris
   sandbox data get <twin>` per the manual), and an app with its own connect flow
   mints its own against the identity twin.

Nothing else is needed, and it is worth knowing how little that is. Measured: the
process ran with no `veris` binary, no Veris key or sandbox id, no proxy variable, and
no CA material at all. A sandbox URL is plain HTTP, so the certificate work the
container tier sometimes needs for an SDK that bundles its own roots does not arise
here.

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

It does not weaken the promotion rule, which is never to promote a task sandbox. It
does not weaken the identity rules in [twin.md](twin.md), or the fault discipline in
[faults.md](faults.md).

`build` and `fix` work unchanged here. Wherever a gate says "through `veris run`, a
receipt per run", the direct-tier equivalent is "against the wired sandbox, trace per
run". Note the newest trace id before the run, read back with
`veris sandbox trace --service <twin> --since <id>` after it, and count the difference
between them as this run's traffic. A shared sandbox's trace is not per-process the way
a receipt is. Trace ids are each twin's own sequence, so the watermark is per twin. A
suite that needs per-test isolation isolates by data, with its own root resources per
test, rather than by sandbox.
