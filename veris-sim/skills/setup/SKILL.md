---
name: setup
description: Wire this repository to a Veris environment, once - the credential, the environment, the transport (veris-proxy + docker, or --direct for apps whose config carries the base URLs), one smoke run with proof of arrival, and, when the app works with files, the state they live in. Run before build or fix. Run when the engineer names this command.
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

`scripts/preflight.sh` in this skill's directory checks the preconditions and
reports **every** one that fails in a single run. Under the direct tier add
`--direct`, which skips the binary/docker/image checks; without it all three are
required. An environment id given with the command overrides
`VERIS_ENVIRONMENT_ID`; service names given with the command seed the step-3
create question.

**Where to run it from.** On a first run nothing is staged yet, so invoke it from
this skill's own directory: derive that absolute path from the path of the file
you are reading, confirm it with `test -f <that path>/scripts/preflight.sh`, and
run it there. Step 5 then copies it into `.veris/bin/`, and every later run —
here, and in `build` and `fix` — uses `sh .veris/bin/preflight.sh` instead.

**Pass the version you are running.** Add `--plugin-version 0.6.6` to every
invocation. A staged copy cannot know which version is loaded, so unless it is
told it cannot notice that it is out of date; without the flag it says
`VERSION_UNCHECKED` rather than guessing.

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

It names every missing precondition in one pass, each with its fix on the same
line — binary, docker, environment. Fix them together, then run it again; a
check whose own precondition failed reports that rather than a second, derived
failure. Installing
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

**Either tier, `.veris/setup.json` also carries what later tasks would otherwise
re-derive**, each measured here rather than guessed:

- `plugin_version` — the version you passed to preflight;
- `source_roots` — where this repository's production source lives;
- `build_command` and `build_outputs` — the repository's own build, and the
  directories it writes. Without them a later task cannot tell a fresh build
  from a stale one, and says so instead of pretending otherwise;
- `smoke_command` — filled in at step 6: the smallest command that produced a
  non-empty receipt. Most repositories have vendor-facing tests that cannot
  produce one at all; naming the one that can is worth more than a paragraph
  about the ones that cannot.

**Stage the scripts.** Copy `scripts/preflight.sh` from this skill's directory
and `scripts/ledger.sh` and `scripts/record.sh` from the reference directory
beside it into `.veris/bin/`. From here on every command runs them from that one
path, so nothing has to resolve an install location mid-task. Re-running setup
re-stages them, which is how a version mismatch is repaired.

**Ignore what is generated, keep what is measured.** Append these to
`.gitignore` if absent — targeted lines, never a blanket `.veris/`, which would
take `setup.json` and `NOTES.md` with it:

```gitignore
.veris/bin/
.veris/tasks/
```

Then ask once, and record the answer as `artifact_policy`: a task's diagnosis,
ledger and execution record are rendered into the change description
(`pr-body`, the default), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit` — say plainly that this merges into the
default branch and accumulates one directory per task). Under `commit`, drop the
`.veris/tasks/` line above.

## 6. Prove it

Container tier: `.veris/run.sh -- <the smallest test that calls the
dependency>`. The proxy prints a receipt — requests per service; an empty one
exits 3. **Not done until the receipt names the environment's service with a
count above zero.** Write the command that did it into `.veris/setup.json` as
`smoke_command`, exactly as run.

Direct tier has no receipt; the twin's trace is the trust anchor. Run the
smallest piece of the application that calls the dependency, then
`GET {control_url}/veris/requests` on that service. **Not done until the
trace shows the application's own calls with a count above zero** — a green
smoke with an empty trace means the app called the real vendor, not the
sandbox. A certificate error against a mapped host is an SDK bundling its own
CA — [../veris-reference/trust.md](../veris-reference/trust.md); other signals —
[../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md).

Either tier: alongside `.veris/setup.json`, write `.veris/NOTES.md` — what this
session measured about the environment that a later task will need. `build` and
`fix` read it first; a fact left only in this transcript dies with it.

Use these headings, and write *measured* under each or *not measured* — never
leave one out, because a heading with nothing under it is itself a finding, and
the next task can decide whether to go and get it:

- **What this twin cannot represent.** No endpoint lists a service's coverage
  ([troubleshooting.md](../veris-reference/troubleshooting.md)), so whatever you
  established here is the only record of it.
- **Identity and matching.** Which fields the service treats as the same record,
  and any normalizing, truncating or joining it does on the way.
- **Errors and the dedup key.** Which failure classes bind to an
  idempotency/dedup key and replay on reuse, and which leave the key free. A fix
  that retries is built on this answer.
- **Credentials and versions.** The shape a key must have, the API version
  pinned, and anything a made-up value gets away with.
- **Where the repo's own tests do not reach the vendor.** Suites that mock
  in-process produce a green with an empty receipt.
- **Anything the twin got wrong.**

Report the receipt line; then step 7.

## 7. Files, when the application works with them

Skip this when the application does not work with files. When it does —
uploads, attachments, documents — set them up once, so every later
sandbox starts with the files instead of each task loading them again:

1. Create a sandbox (`create_sandbox`), or use the direct-tier one.
2. Seed the rows the files hang off — an owner, a folder, a repository — in
   the shapes `/veris/schema` names, or pick an owner already in the sandbox.
3. Post the files with that owner through `/veris/files` where the
   manual shows it, or through the vendor's own upload API where files are
   attachments — rows first, files second, as
   [../veris-reference/state.md](../veris-reference/state.md) lays out.
4. Read them back and check the SHA-256 in each row against the local file.
5. Ask the engineer, then `promote_sandbox`. This is the one place a
   command promotes, and only with a yes; `build` and `fix` never do.
6. Write what is in the sandbox — owners, paths, hashes — into `.veris/NOTES.md`.

Rows-only state is cheap to seed per task and do not need this. Report
and stop: `build` or `fix` takes the task.

Ask before installing the binary or sending repository code anywhere new.
