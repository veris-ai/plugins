# Transport: what is specific to `veris-proxy`

## The container tier

Everything runs through `veris-proxy run --image ...`. The proxy runs in its
own container and the test image runs in a second one sharing its network
namespace; a kernel redirect moves the traffic below every library, so
nothing in the process under test has to cooperate and every runtime is
covered. The image needs no entrypoint change and no particular base, and
runs with every capability dropped — an entrypoint that switches users needs
`--cap-add SETUID --cap-add SETGID`, or an image built to run as that user.
Everything else sits on the proxy's own container.

*Trust* is still decided in-process. An SDK that ships its own CA bundle
decides it alone; `integration-testing` carries that diagnosis.

The binary also has a host tier — `run` without `--image`, proxy environment
variables only. It covers only libraries that honour those variables and its
gaps are silent, so it is never used for code under test. A discovery probe
is not code under test; `discovering-vendor-behavior` says when curl or a
script straight at the sandbox is the right tool.

There is no proxy config to maintain. The run names an `--environment`, and
the routing — which production hostnames map to which services — comes from
the control plane plus a table measured against the real vendors and embedded
in the binary. Never write hosts files by hand.

## The image

Any image that runs the tests: the team's existing test image, or a stock
toolchain image with the repository bind-mounted. Three things are specific
to the proxy:

- The proxy does not intercept package registries by default, so dependency
  resolution inside the container works as it always did.
- Nothing Veris-specific goes in the image — no `VERIS_API_KEY`, no
  credentials, no CA material, no proxy configuration. The proxy hands all of
  that to the workload at run time.
- The image must not run as uid 14741, the uid the kernel redirect exempts
  for the proxy itself. The CLI refuses with an explanation if it does;
  `--proxy-uid` moves the exemption.

When deriving a working image took real work, record it as
**`Dockerfile.veris`** at the repository root, with a header naming the build
tag and `.veris/run.sh` as the way to run it, so no later session re-derives
it. If the repository cannot run its tests in a container at all, stop and
tell the user; the host tier is not a fallback.

## What the run hands the workload

- `-v`, `-e`, `-w` pass through to the workload container. Credentials the
  code expects still come from its environment, exactly as in production —
  the sandbox publishes known-good credentials readable at
  `{control_url}/veris/data`; the service's manual names where.
- Non-HTTP services are **handed over, not proxied**: a database service's
  connection string arrives in the workload's environment under the exact
  variable the platform names for it (`DATABASE_URL` for Postgres),
  automatically. Do not wire it yourself, and do not read "postgres: not
  proxied" in the startup log as a gap: it names the variable the value went
  to. An explicit `-e DATABASE_URL=...` of your own still wins. Seed structure
  with `POST {control_url}/veris/seed` using `schema_sql` or a shipped
  `sql_file`; reconnect after a sandbox reset.
- With no command after `--`, the image's own ENTRYPOINT/CMD run untouched.
- `--ttl-minutes` bounds a sandbox leak if teardown never runs.
