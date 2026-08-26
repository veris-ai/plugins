---
name: setup
description: Wire this repository to a Veris environment, once - the credential, the environment, the transport (veris-proxy + docker, or --direct for apps whose config carries the base URLs), and one smoke run with proof of arrival. Run before build or fix. Run when the engineer names this command.
argument-hint: "[environment-id | service names...] [--direct]"
disable-model-invocation: true
---

Wire this repository to a Veris environment, once; re-running skips what
still holds. Two transports, one contract each:

- **Container (default).** The code is never modified and never told —
  `veris-proxy` reroutes its outbound HTTP(S) into a sandbox from outside
  the process. Leaves `.veris/run.sh` (the exact `veris-proxy run`
  invocation), `.veris/setup.json`, and `Dockerfile.veris` only when
  deriving an image took real work.
- **Direct (`--direct`).** For an application whose own configuration reads
  each service's base URL from the environment variable the platform names
  (its `env_hint`) — then pointing those variables at a sandbox IS the
  shipped code path, and no proxy or docker is involved.
  [reference/direct.md](reference/direct.md) carries the contract; step 2
  gates entry. Leaves `.veris/setup.json` with `"tier": "direct"`.

`scripts/preflight.sh` in this skill's directory checks the preconditions —
invoked as `sh scripts/preflight.sh --direct [env-id]` under the direct
tier, which skips the binary/docker/image checks; without the flag it
requires all three. An environment id given
with the command overrides `VERIS_ENVIRONMENT_ID`; service names given with
the command seed the step-3 create question.

## 1. Credential

`sh scripts/preflight.sh` (with `--direct` first when that tier was
requested) reports the credential first. If `VERIS_API_KEY` is not
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

`--direct` is not that fallback, and step 2 refuses it unless it holds: every
service base URL the code uses must come from its environment (the exact
`env_hint` variables), with no vendor hostname hardcoded on the tested path.
Check the code, not the claim — a hardcoded host means the proxy tier, full
stop. What `--direct` skips is the binary, docker, and the image; credential
and environment checks run unchanged.

## 3. Environment

`VERIS_ENVIRONMENT_ID` set → `GET ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID`
(`X-API-Key`; or the `get_environment` MCP tool) must list the services this code
calls. Not set → `GET ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments` lists the engineer's;
ask which. Create one only after asking, and in the question name the
services you inferred from the code — the reply may add or drop names;
check each against `GET /v1/services`, the catalogue. Then
`POST /v1/environments` `{"name":…,"services":[…]}`.

## 4. Image (container tier)

Skip this step under `--direct`. Every container run uses `--image`. Derive one from the repository's own test setup —
anything that runs the tests, nothing Veris-specific; `Dockerfile.veris`
only if that took real work. [reference/transport.md](reference/transport.md)
only when the smoke run fails on what the proxy hands the workload.

## 5. Record

Under `--direct`: create a sandbox (`create_sandbox`, or
`POST ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`), read
each service's `env_hint` and `url` from `get_sandbox`, and set those
variables where the application's environment actually comes from — a
platform Secrets pane, an env file, an export. Some panes are human-only
(Replit's is — measured): then name each variable and value and wait for the
engineer to paste. Write `.veris/setup.json` with `tier`, `environment_id`,
`sandbox_id`, and the variable names; [reference/direct.md](reference/direct.md)
carries sandbox lifetime and rotation. Skip `.veris/run.sh`.

Container tier: write `.veris/run.sh` and `.veris/setup.json`:

```sh
#!/usr/bin/env sh
# Written by /veris-sim:setup. Flags before -- pass through; a command after -- replaces the default.
# VERIS_SANDBOX_ID set: attach to that sandbox (build and fix make one per task). Unset: a fresh one per run.
set -eu
if [ -n "${VERIS_SANDBOX_ID:-}" ]; then target="--sandbox $VERIS_SANDBOX_ID"
else target="--environment ${VERIS_ENVIRONMENT_ID:?}"; fi
run() { exec veris-proxy run $target --image myrepo-veris-tests -v "$PWD:/work" -w /work "$@"; }
for arg in "$@"; do [ "$arg" = "--" ] && run "$@"; done
run "$@" -- make integration
```

Mounts stay under the repository tree or a known dependency cache. Tell the
engineer both files exist and are worth committing.

## 6. Prove it

Container tier: `.veris/run.sh -- <the smallest test that calls the
dependency>`. The proxy prints a receipt — requests per service; an empty one
exits 3. **Not done until the receipt names the environment's service with a
count above zero.**

Direct tier has no receipt; the twin's trace is the trust anchor. Run the
smallest piece of the application that calls the dependency, then
`GET {control_url}/veris/requests` on that service. **Not done until the
trace shows the application's own calls with a count above zero** — a green
smoke with an empty trace means the app called the real vendor, not the
sandbox. A certificate error against a mapped host is an SDK bundling its own
CA — [../veris-reference/trust.md](../veris-reference/trust.md); other signals —
[../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md).

Either tier: alongside `.veris/setup.json`, write `.veris/NOTES.md` — what
this session measured about the environment that a later task will need: a
capability the twin lacks, a fact about the world's data, a matching or
identity quirk, anything the twin got wrong. `build` and `fix` read it
first; a fact left only in this transcript dies with it. Report the
receipt line and stop: `build` or `fix` takes the task.

Ask before installing the binary or sending repository code anywhere new.
