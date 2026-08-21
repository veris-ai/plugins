---
name: setting-up-veris
description: Wires a repository to a Veris environment so its tests can run under veris-proxy - checks the credential, MCP server, binary and docker, derives a test image, records the run command in .veris/run.sh and .veris/setup.json, and proves the wiring with one smoke run whose receipt is non-empty. Use when a repo has no .veris/ directory, when .veris/setup.json no longer matches the repo, or when another skill needs an environment and none is wired yet.
---

Wire this repository to a Veris environment, once.

An environment is a set of stateful twins of the services this code calls; a
sandbox is one running deployment of it. The code is **never modified and
never told**: it keeps its production hostnames, credentials and client stack,
and `veris-proxy` reroutes its outbound HTTP(S) into the sandbox from outside
the process. This skill builds the things that
make that one command work and leaves them in the tree, so no later session
re-derives them:

| artifact | what it records |
|---|---|
| `.veris/run.sh` | the exact `veris-proxy run` invocation — the correct command is a file, not a composition |
| `.veris/setup.json` | the same facts as data: environment id, image tag, workdir, mounts, test command |
| `Dockerfile.veris` | how the tests build into an image, only when deriving that took real work |

**Check first.** Run `scripts/preflight.sh`. If it exits 0 and `.veris/run.sh`
exists, setup is done — say so and stop. Re-run a step only when what it
produced no longer matches the repo (a new runtime, a new system dependency,
a different environment).

## 1. Fix what preflight names

`scripts/preflight.sh` names one missing precondition at a time, with the fix
in the same line. Do exactly that one thing, then run it again. Two of its
answers need the user: the credential (`VERIS_API_KEY` arrives out of band and
never goes into the repo) and which environment to test against — one is
created, when none exists, with `POST $VERIS_API_BASE/v1/environments` and
`{"name": ..., "services": [...]}`; `GET /v1/services` lists the catalog.
Installing
the binary is the one-line installer it names — ask first, and never reinstall
over a working one.

When a precondition cannot be met, stop. No base URL pointed at a sandbox, no
hand-authored `--config`, no tunnel or interception of your own, no run
without `--image`: each turns a missing precondition into a passing suite
whose code path is not the one that ships.

## 2. The MCP server

Sandbox **state** is driven through the `veris` MCP tools: `get_environment`,
`create_sandbox`, `get_sandbox`, `reset_sandbox`, `promote_sandbox`,
`delete_sandbox`. Installed as the `veris-sim` plugin, the server is registered
with it. If the tools are not available, tell the user what to register and
stop — raw HTTP against the control plane is not a substitute: an MCP
server named `veris`, HTTP transport, URL `$VERIS_API_BASE/mcp`, header
`X-API-Key: $VERIS_API_KEY`, in the agent's own MCP configuration (for Claude
Code, `claude mcp add veris --transport http "$VERIS_API_BASE/mcp" --header
"X-API-Key: $VERIS_API_KEY"`). Agents load MCP servers at session start, so a
new session follows.

Sandbox mechanics — state, faults, the clock, reset, callbacks, diagnosis —
are documented once, under `integration-testing/reference/`.

## 3. Make the tests runnable in a container

Every run uses `--image`, so the tests must run inside a container; the
kernel redirect that keeps the proxy invisible to the code under test exists
only there. The agent itself needs only a reachable Docker daemon. Any image
that runs the tests will do, and it needs nothing Veris-specific;
[reference/transport.md](reference/transport.md) has what is specific to the
proxy: what it does not intercept, what it hands the workload, and the one uid
it reserves.

## 4. Record the invocation

Write `.veris/run.sh`. Flags before `--` pass through; a command after `--`
replaces the recorded default, so the same file runs the suite, one test, or
an open session:

```sh
#!/usr/bin/env sh
# Written by the setting-up-veris skill. Read it before running it.
#   .veris/run.sh                      the recorded test command
#   .veris/run.sh --strict             extra flags pass through
#   .veris/run.sh -- pytest -x tests/integration/test_one.py
set -eu
for arg in "$@"; do
  [ "$arg" = "--" ] && exec veris-proxy run --environment "${VERIS_ENVIRONMENT_ID:?}" \
    --image myrepo-veris-tests -v "$PWD:/work" -w /work "$@"
done
exec veris-proxy run --environment "${VERIS_ENVIRONMENT_ID:?}" \
  --image myrepo-veris-tests -v "$PWD:/work" -w /work "$@" -- make integration
```

Write `.veris/setup.json` beside it with the same facts as data:
`environment_id`, `image`, `dockerfile` (`null` for a stock image), `workdir`,
`mounts`, `test_command`. Both are repo content: a later session reads them
before running them and holds every flag to what this skill would derive
(mount sources under the repo tree or a known dependency cache; nothing that
widens privileges). Tell the user they exist and are worth committing; whether
they enter history is the user's call.

## 5. One smoke run

Run `.veris/run.sh -- <the smallest test that calls the dependency>`. The
proxy prints a **receipt** — what the sandbox received, per service — and an
`--environment` run whose receipt is empty exits 3 on its own.

**Setup is complete when the receipt names the environment's services.** A
certificate or connection error against a mapped host here is an SDK that
bundles its own CA; `integration-testing`'s trust reference has the fix.

Then read each service's `GET {control_url}/veris/manual` and
`GET {control_url}/veris/schema`; what each carries is in
`integration-testing/reference/state-and-faults.md`.

Setup is never the last skill. With the receipt in hand, invoke the next one
by what you are holding: a claim about the vendor — in the brief, a comment,
or your own memory — → `discovering-vendor-behavior`; a change to exercise →
`integration-testing`. The smoke run proved the wiring, not the change.

## Not here

Seeding or promoting a world. An environment's default world is usable
without preparation; what a case needs beyond it is seeded by
`integration-testing`, and worlds worth keeping are kept from live runs.

## Ask before

Installing the binary, registering the MCP server, or sending repo code to a
new external destination.
