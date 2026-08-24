---
name: setup
description: Wire this repository to a Veris environment, once - the credential, veris-proxy, docker, the environment, a test image, the recorded run command, and one smoke run with a non-empty receipt. Run before build or fix.
argument-hint: "[environment-id]"
disable-model-invocation: true
---

Wire this repository to a Veris environment, once; re-running skips what
still holds. The code is never modified and never told — `veris-proxy`
reroutes its outbound HTTP(S) into a sandbox from outside the process. This
command leaves in the tree what makes one run work: `.veris/run.sh` (the
exact `veris-proxy run` invocation), `.veris/setup.json` (the same facts as
data: `environment_id`, `image`, `dockerfile` or `null`, `workdir`, `mounts`,
`test_command`), and `Dockerfile.veris` only when deriving an image took real
work. `scripts/veris.sh` in this skill's directory does the mechanics (`sh`).
An environment id given with the command overrides `VERIS_ENVIRONMENT_ID`.

## 1. Credential

`veris.sh preflight` reports the credential first. If `VERIS_API_KEY` is not
set, say exactly this and end the turn:

> Run this in your terminal, then tell me when it's done:
> `echo 'export VERIS_API_KEY=<your key>' >> ~/.zshrc && source ~/.zshrc`

(`~/.bashrc` when `$SHELL` is bash.) On their reply, run preflight again —
it reads the variable in a fresh shell. Say "VERIS_API_KEY is set"; never
print the value; write it nowhere. The `veris` MCP server read the
environment at session start: say a restart is needed before its tools
work; nothing here needs them.

## 2. Preflight

It names one missing precondition at a time with the fix on the same line —
binary, docker, environment. Do that one thing, run it again. Installing
the binary: ask first, never over a working one. What preflight cannot
satisfy stops setup — no base-URL override, hand-written config, or run
without `--image`; each proves a code path that is not the one that ships.

## 3. Environment

`VERIS_ENVIRONMENT_ID` set → `veris.sh env` must list the services this code
calls. Not set → `GET $VERIS_API_BASE/v1/environments` lists the engineer's;
ask which. Create one only after asking: `POST /v1/environments`
`{"name":…,"services":[…]}`; `GET /v1/services` is the catalogue.

## 4. Image

Every run uses `--image`. Derive one from the repository's own test setup —
anything that runs the tests, nothing Veris-specific; `Dockerfile.veris`
only if that took real work. [reference/transport.md](reference/transport.md)
only when the smoke run fails on what the proxy hands the workload.

## 5. Record

Write `.veris/run.sh` and `.veris/setup.json`:

```sh
#!/usr/bin/env sh
# Written by /veris-sim:setup. Flags before -- pass through; a command after -- replaces the default.
set -eu
for arg in "$@"; do
  [ "$arg" = "--" ] && exec veris-proxy run --environment "${VERIS_ENVIRONMENT_ID:?}" \
    --image myrepo-veris-tests -v "$PWD:/work" -w /work "$@"
done
exec veris-proxy run --environment "${VERIS_ENVIRONMENT_ID:?}" \
  --image myrepo-veris-tests -v "$PWD:/work" -w /work "$@" -- make integration
```

Mounts stay under the repository tree or a known dependency cache. Tell the
engineer both files exist and are worth committing.

## 6. Prove it

`.veris/run.sh -- <the smallest test that calls the dependency>`. The proxy
prints a receipt — requests per service; an empty one exits 3. **Not done
until the receipt names the environment's service with a count above
zero.** A certificate error against a mapped host is an SDK bundling its own
CA — [reference/trust.md](reference/trust.md); other signals —
[reference/troubleshooting.md](reference/troubleshooting.md). Report the
receipt line and stop: `build` or `fix` takes the task.

Ask before installing the binary or sending repository code anywhere new.
