# The run: the application's own code against the twin

Read this to exercise a change, and to know what a green proves. `veris run` puts the
application's unmodified code, production hostnames, credentials and client stack in
front of the sandbox: it reroutes the application's outbound HTTP(S) from outside the
process. The run ends with a **receipt** of what the sandbox received. Vendor MCP
servers are covered too, for the twins that offer one: keep the production MCP URL in
the app.

## Two tiers

**Container tier, `--image <tag>`.** The proxy runs in its own container and the test
image runs in a second one sharing its network namespace. A kernel redirect moves the
traffic below every library, so nothing in the process under test has to cooperate
and every runtime is covered. The image needs no entrypoint change and no particular
base. It runs with every capability dropped; an entrypoint that switches users needs
`--cap-add SETUID --cap-add SETGID`, or build the image to run as that user. `ALL` and
`SYS_ADMIN` are refused. This is the tier for code under test.

**Host tier, no `--image`.** The command runs as a local process with proxy and
certificate environment variables set. It covers only libraries that honour those
variables, and its gaps are silent, so it is never used for code under test. A quick
probe with curl is fine there.

A third tier, for a machine with no Docker daemon, is [daytona.md](daytona.md): the
same unmodified code in a Daytona sandbox wired to the twin, with the trace as the
receipt.

Trust is decided in-process in both tiers: an SDK that ships its own CA bundle
refuses the proxy's certificate even when routing worked. `--patch-bundled-cas`
handles that in the container tier; see
[troubleshooting.md](troubleshooting.md).

There is no proxy configuration to maintain. Which production hostnames map to which
twins comes from the control plane. It is the only source: the hostnames are measured
against the real vendors and served with every sandbox. Never write hosts files by
hand. A twin the control plane serves no hostname for is not intercepted at all; its
URL is handed to your command under its env hint instead, and the run says so.
`--route <twin>=<host>[/prefix]` routes a hostname the control plane did not serve,
such as a regional endpoint. It **replaces** that twin's served routes for the run, so
repeat it for every hostname the twin should still answer for:
`--route stripe=api.stripe.com --route stripe=api.stripe.eu`.

## The image

Any image that runs the tests: the team's existing test image, or a stock toolchain
image with the repository bind-mounted. Three things are specific to the proxy:

- Package registries are not intercepted by default, so dependency resolution inside
  the container works as it always did.
- Nothing Veris-specific goes in the image: no key, no credentials, no certificate,
  no proxy configuration. The run hands all of that to the workload.
- The image must not run as uid 14741, the uid the redirect exempts for the proxy
  itself. The CLI refuses with an explanation; `--proxy-uid` moves the exemption.

When deriving a working image took real work, record it as `Dockerfile.veris` at the
repository root with a comment naming the build tag. If the repository cannot run its
tests in a container at all, stop and tell the engineer; the host tier is not a
fallback.

## What the run hands the workload

- `-v`, `-e`, `-w` pass through to the workload container. Credentials the code
  expects still come from its environment, as in production. The sandbox publishes
  known-good ones; the twin's manual names where.
- A twin with no hostname to intercept is **handed over, not proxied**. A database
  twin's connection string, or a data-plane twin's URL such as Yente's, arrives in the
  workload's environment automatically. It arrives under the variable the platform
  names for it: `DATABASE_URL` for Postgres, `YENTE_API_BASE` for Yente. Do not wire it
  yourself. The line
  `veris: postgres: not proxied; handed DATABASE_URL=…` is not a gap: it names the
  variable the value went to. A twin the control plane served no hostname for is handed
  over the same way and prints the same line. That one is not by design: run
  `veris doctor` and read its vendor-hostnames line, which names every twin the plane
  serves no hostname for. An explicit `-e` of your own for that variable still wins. A
  `--require-service` on such a twin is judged on the sandbox's ledger alone, the only
  one its traffic reaches. Seed a database's structure with `veris sandbox data add`
  and a `{"postgres": {"sql": "schema.sql"}}` entry; reconnect after a reset.
- With no command after `--`, the image's own ENTRYPOINT and CMD run untouched.
- Mounts stay under the repository tree or a known dependency cache.

## Flags that change the verdict

| flag | what it does |
|---|---|
| `--require-service <twin>[:n]` | fail with exit 3 unless the sandbox received at least n requests to that twin (`proxy.require_service` in `.veris/twin.yaml` sets the default) |
| `--require-host <host>[:n]` | the same, by intercepted hostname rather than twin |
| `--require-callback <path>[:n]` | the same for callbacks delivered to the app; `*` for any path ([webhooks.md](webhooks.md)) |
| `--strict` | a request to a hostname that is not one of the twins is refused instead of reaching the real internet: the claim "the code reached nothing but the sandbox" |
| `--fresh` | up, run, down in one command: a sandbox per run, data files included, deleted after; `--keep` leaves it running as this folder's; `--ttl <minutes>` bounds its life if teardown never runs. Asserts a non-empty receipt by default |
| `--receipt <path>` | write the receipt as JSON to a file: both ledgers and the verdict, never on stdout |
| `--expose <port>` | a public URL for the app to receive callbacks |
| `--keep-proxy` | leave the proxy container up for inspection |
| `--patch-bundled-cas` | append the proxy's certificate to the SDK-bundled CA files it knows ([troubleshooting.md](troubleshooting.md)) |
| `--cap-add <CAP>` | hand one Linux capability back to the workload; repeatable |
| `--java-truststore <path>` | a JKS truststore holding the proxy's certificate for a JVM client (`--java-truststore-pass` when it is not `changeit`) |

Without `--fresh`, the run attaches to this folder's sandbox, the one `veris up` made,
and leaves it running. Use that for a task: the faults armed and the state read back
are the ones the code met. `--sandbox <id>` attaches to another sandbox; `--env NAME`
picks a different environment's config from `.veris/twin.yaml`.

The run exits with the command's own code, except for three codes of its own:

- **1**: a usage or configuration error.
- **3**: the run never proved its traffic. That is an empty receipt on a fresh run, an
  unmet `--require-*`, or every TLS handshake to a twin rejected, with a line naming
  the next step.
- **4**: indeterminate, because neither ledger could settle an assertion. The sandbox's
  ledger was read only to its cap, or it could not be read and the proxy's count was
  not there to answer.

A `--require-service` passes when either ledger shows the count, and the verdict line
says which side decided when the two disagree. Exit 3 outranks the command's own
failure: a suite that crashed before reaching the sandbox proved nothing about the
integration.

## Working inside a run

To seed, arm and rerun repeatedly against one sandbox in the container tier, start a
session and work inside it:

```
veris run -- sleep infinity &
docker exec "$(docker ps -q -f name=veris-workload-)" sh -lc '<one pass>'   # as often as needed
kill %1     # ends the run and prints the receipt for the whole session
```

Wait for the run to print `sandbox ready sandbox_id=<id>` before the first
`docker exec`; the workload container is named `veris-workload-<pid>` and the proxy's
`veris-proxy-<pid>`.

## What a green proves

A green suite and a receipt prove a change only together, and only from the same run:

- the receipt names the twin the tests were meant to reach; it counts every completed
  request to a twin's hostname, setup traffic included, and `veris sandbox trace`
  says whose it was;
- the run executed the changed code on its way to the vendor: a flow from the boundary
  the task names, with the call the report describes, unchanged. A green earned by
  changing the caller's call proves the caller changed;
- the same flow red before the change and green after it is the strongest form;
- nothing in the repository or its environment was pointed at a sandbox.

A green suite with an empty receipt is not a pass. A red suite whose receipt shows the
traffic arrived is a real integration finding. Only one outcome is silent: a run whose
SDK calls all failed TLS still prints a healthy receipt if anything else in the run
completed a request on that host, a health check or a second client. When the SDK
reports a connection error but the receipt shows traffic for its host, read the paths
in the trace to see whose traffic it was.
