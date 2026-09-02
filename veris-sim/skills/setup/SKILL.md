---
name: setup
description: Wire this repository to a Veris environment - the credential, the environment, the tier (container; --direct for apps whose config carries the base URLs; or hosted, which is measured rather than chosen), one smoke run with proof of arrival, and, when the app works with files, the state they live in. Once per repository; once per session on the hosted tier. Run before build or fix. Run when the engineer names this command.
argument-hint: "[environment-id | service names...] [--direct]"
disable-model-invocation: true
---

Wire this repository to a Veris environment, once — once per session on the
hosted tier; re-running skips what still holds. Three tiers, one contract
each, and one vocabulary for every later gate: **the run command** and **the
receipt**.

- **Container (default).** The code is never modified and never told —
  `veris-proxy` reroutes its outbound HTTP(S) into a sandbox from outside
  the process. Leaves `.veris/run.sh` (the exact `veris-proxy run`
  invocation), `.veris/setup.json`, and `Dockerfile.veris` only when
  deriving an image took real work. The run command is `.veris/run.sh`; the
  receipt is what it prints.
- **Direct (`--direct`).** For an application whose own configuration reads
  each service's base URL from the environment variable the platform names
  (its `env_hint`) — then pointing those variables at a sandbox IS the
  shipped code path, and no proxy or docker is involved.
  [reference/direct.md](reference/direct.md) carries the contract; step 2
  gates entry. Leaves `.veris/setup.json` with `"tier": "direct"`. The run
  command is the application's own; the receipt is the twin's trace,
  `GET {control_url}/veris/requests`.
- **Hosted.** Never chosen: measured, by section 0. Your commands already run
  inside a sandbox the session provisioned, with a twin attached and egress
  intercepted before your first turn, so there is no transport to wire and
  steps 1 through 4 do not apply. Leaves `.veris/session.md`, per session;
  `.veris/setup.json` as step 5 says. The run command is the one
  `session.md` names; the receipt is the tool that reports what the twin
  received.

`scripts/preflight.sh` in this skill's directory checks the preconditions and
reports **every** one that fails in a single run. Under the direct tier add
`--direct`, which skips the binary/docker/image checks; without it all three are
required. Under the hosted tier add `--hosted`: it skips credential,
environment, binary, docker and image, keeps `jq` and the staged-script
version, and requires a finished `.veris/session.md` — so it runs once, from
`.veris/bin/`, at the end of step 6. An environment id given with the command
overrides
`VERIS_ENVIRONMENT_ID`; service names given with the command seed the step-3
create question.

**Where to run it from.** On a first run nothing is staged yet, so invoke it from
this skill's own directory: derive that absolute path from the path of the file
you are reading, confirm it with `test -f <that path>/scripts/preflight.sh`, and
run it there. Step 5 then copies it into `.veris/bin/`, and every later run —
here, and in `build` and `fix` — uses `sh .veris/bin/preflight.sh` instead. On
the hosted tier that first-run path does not exist — this directory is not in
the sandbox — and the copy section 0 fetches into `.veris/bin/` is the only one.

**Pass the version you are running.** Add `--plugin-version 0.8.0` to every
invocation. A staged copy cannot know which version is loaded, so unless it is
told it cannot notice that it is out of date; without the flag it says
`VERSION_UNCHECKED` rather than guessing.

## 0. What this session can reach

Settled once, before step 1 and before any subagent exists, and stated as a
fact in every subagent brief. Call the tool that reports what the twin
received, with no argument — the per-service form drops the header this reads.

| the tool answers | reading |
|---|---|
| a header naming a twin — `Veris receipt — twin <id>` | **hosted.** The twin id is on that line. Continue below. |
| `No Veris twin is attached to this sandbox, so there is no receipt to read.` | **stop, before anything else.** A sandbox exists, but the tool cannot report on this session's twin, and a receipt that cannot be read is a gate with no proof behind it. Name `VERIS_API_KEY` and `VERIS_ENVIRONMENT_ID`, say a new session is required, write nothing. |
| no such tool | **not hosted.** Skip the rest of this section; `--direct` or its absence decides between the other two tiers, unchanged. |

Nothing else is a tell. `VERIS_SANDBOX_ID` decides nothing: the container tier
exports it per task, so any `build` past Gate 1 has it in its shell; once the
tool has said hosted it is a second reading of the same id. Your own tool list
decides nothing either: a subagent may not carry the tool, and a tier derived
twice is one task on two tiers.

Hosted, four readings follow. Each is measured here, per session, and none is
a property of a platform name. Nothing in a reference file is needed to take
them, and none can be opened from here: on this tier your `read` runs inside
the sandbox and the skill files sit outside it. A link you cannot open is not
a gate you may skip — every gate in `setup`, `build` and `fix` stands on the
skill text and on files you wrote here, and where one does not, stop.
[reference/platforms.md](reference/platforms.md) is what other sessions
measured, dated; it closes nothing.

**1. Where the admin endpoints are, and that they answer.** Every `/veris/*`
call in `build` and `fix` goes to a service's `control_url`. Obtain it with
`get_sandbox` (MCP) and the twin id from the header — the REST form in
`twin.md` needs `VERIS_API_KEY` and `VERIS_ENVIRONMENT_ID`, which are the
host's and not in this shell. Then, per service:

```sh
curl --fail-with-body -sS "$CONTROL_URL/veris/schema" | jq -e '.properties | type == "object"'
```

**Not done until this exits 0 for every service** — the twin answered `200`
with its schema. Veris puts the control-plane hosts on every sandbox's
allowlist, so there is no reduced mode behind anything else: no URL
obtainable, a status that is not `200`, or no answer at all means setup is
unfinished — stop, and say which.

**2. What a host the twin does not answer for looks like from here.** Keep the
body; it is what tells a boundary's refusal from a vendor's own.

```sh
curl --fail-with-body -sS -D - -o /tmp/veris-egress-probe.body -m 10 https://example.com
head -1 /tmp/veris-egress-probe.body
```

- A `2xx` from the real host → `egress: open`. A connection error then proves
  nothing about interception, a vendor the twin does not model is called for
  real with real credentials, and only the receipt says what arrived.
- Any other HTTP status → `egress: boundary-refused`. The host itself does not
  refuse, so the status and the body's first line are the boundary's
  signature; record both. A later refusal matching them is the boundary, not
  the vendor, and means the host is not mapped; one that does not match is the
  vendor's own.
- No HTTP status at all — resolution, connect, or timeout → `egress: unreachable`.
  A connection error is the boundary.

**3. Whether the scripts can be staged.** The skill files are not in the
sandbox, so `.veris/bin/` cannot be filled by copying. Two routes, in order;
record the one that worked and the version it staged:

```sh
v=0.8.0; mkdir -p .veris/bin
npm pack "@veris-ai/veris-sim-opencode@$v" && tar -xzf "veris-ai-veris-sim-opencode-$v.tgz" &&
  cp package/skills/setup/scripts/preflight.sh \
     package/skills/veris-reference/scripts/ledger.sh \
     package/skills/veris-reference/scripts/record.sh .veris/bin/       # staging: npm
```

```sh
for f in setup/scripts/preflight.sh veris-reference/scripts/ledger.sh veris-reference/scripts/record.sh; do
  curl --fail-with-body -sSL -o ".veris/bin/$(basename "$f")" \
    "https://raw.githubusercontent.com/veris-ai/plugins/opencode-v$v/veris-sim/skills/$f"
done                                                                     # staging: raw
```

Both fail → `staging: unreachable`, and **setup is unfinished — stop and say
so.** There is no discipline-without-tooling path: `ledger.sh` is what closes
`fix`'s Gate 4, and it dies without `jq` (every row is JSON). `command -v jq`
absent: install it the way this sandbox installs packages, once; still absent
is the same stop.

**4. Whether `gh` works here.** `gh auth status` exits 0 →
`issue_and_pr: sandbox`; `gh` absent or unauthenticated →
`issue_and_pr: engineer`, and the engineer pastes the issue and takes the PR
body from the transcript.

Write `.veris/session.md` at the repository root inside the sandbox — facts
only, these lines and no others; it is regenerated every session and `build`
and `fix` read it before their first gate:

```
twin: sbx_7f3a…
tier: hosted
lifecycle: session          # the sandbox is not yours: create nothing, delete nothing
control_url: stripe https://stripe-7f3a.twin.veris.ai   # one line per service; GET /veris/schema answered 200
egress: boundary-refused    # <status>; body begins "<first line, verbatim>"
staging: npm 0.8.0          # the route, then the version staged into .veris/bin/; jq present
issue_and_pr: sandbox       # gh present and authenticated here
run:                        # written by step 6, once a smoke run has reached the twin
receipt: the receipt tool, called with no argument
```

`run:` stays empty until step 6; an empty `run:` means setup is unfinished.
Steps 1 through 4 do not apply on this tier; go to step 5.

## 1. Credential

Hosted: skip. The credential is the session's, read on the host before your
first turn; it is not in this shell, and nothing here needs it.

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

Hosted: skip. Binary, docker and image do not apply, and the environment is
not checkable from here; the one preflight this tier runs is step 6's, with
`--hosted`.

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

Hosted: skip. The environment is the session's; the services it holds are the
ones the receipt header lists, each with its `control_url` from section 0.

`VERIS_ENVIRONMENT_ID` set → `GET ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID`
(`X-API-Key`; or the `get_environment` MCP tool) must list the services this code
calls. Not set → `GET ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments` lists the engineer's;
ask which. Create one only after asking, and in the question name the
services you inferred from the code — the reply may add or drop names;
check each against `GET /v1/services`, the catalogue. Then
`POST /v1/environments` `{"name":…,"services":[…]}`.

## 4. Image (container tier)

Skip this step under `--direct` and on the hosted tier. Every container run uses `--image`. Derive one from the repository's own test setup —
anything that runs the tests, nothing Veris-specific; `Dockerfile.veris`
only if that took real work. [reference/transport.md](reference/transport.md)
only when the smoke run fails on what the proxy hands the workload.

## 5. Record

Hosted: the sandbox and the twin are the session's, so there is nothing to
create and no variable to set. `.veris/setup.json` carries `tier`,
`plugin_version`, `source_roots`, `build_command`, `build_outputs`,
`smoke_command` (step 6) and `artifact_policy` — no `environment_id` and no
`sandbox_id`; those are the session's and live in `.veris/session.md`. A
`setup.json` already present and recording another tier is not rewritten:
leave every field alone, write the hosted facts to `session.md` only, and note
the mixed wiring at the top of `.veris/NOTES.md`. Skip `.veris/run.sh`.

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

**Every tier, `.veris/setup.json` also carries what later tasks would otherwise
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
re-stages them, which is how a version mismatch is repaired. On the hosted tier
section 0 already fetched them — `staging:` in `.veris/session.md` says by
which route, and which version — and a re-run fetches again.

**Ignore what is generated, keep what is measured.** Append these to
`.gitignore` if absent — targeted lines, never a blanket `.veris/`, which would
take `setup.json` and `NOTES.md` with it:

```gitignore
.veris/bin/
.veris/tasks/
.veris/session.md
```

Then ask once, and record the answer as `artifact_policy`: a task's diagnosis,
ledger and execution record are rendered into the change description
(`pr-body`, the default), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit` — say plainly that this merges into the
default branch and accumulates one directory per task). Under `commit`, drop the
`.veris/tasks/` line above. On the hosted tier `commit` is not offered, and the
question says so: `.veris/tasks/` dies with the session, and what a sandbox
commits reaches the checkout only by the session's own sync, which no gate
depends on.

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

Hosted: the run command is the repository's own — the smallest piece of the
application that calls the dependency, run as it stands; no `run.sh`, no exit
code to read. Then the receipt: the tool, with no argument. **Not done until it
names the environment's service with a count above zero.** `ZERO requests
reached the twin` is the finding, not a formality: from inside the sandbox a
run that never reached the dependency and one that did are indistinguishable,
and only the receipt separates them. Write the command that did it to `run:`
in `.veris/session.md` and to `smoke_command` in `.veris/setup.json`, exactly
as run. Then `sh .veris/bin/preflight.sh --hosted --plugin-version 0.8.0`: it
reads `session.md`, exits 2 on a missing `twin:` or an empty `run:`, and
reports a staged script older than the version passed. **Not done until it
exits 0.**

Every tier: alongside `.veris/setup.json`, write `.veris/NOTES.md` — what this
session measured about the environment that a later task will need. `build` and
`fix` read it first; a fact left only in this transcript dies with it.

Use these headings, and write *measured* under each or *not measured* — never
leave one out, because a heading with nothing under it is itself a finding, and
the next task can decide whether to go and get it:

- **What this twin cannot represent.** Whatever you established here is the
  only record of it.
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

1. Create a sandbox (`create_sandbox`), or use the direct-tier one, or the
   session's on the hosted tier.
2. Seed the rows the files hang off — an owner, a folder, a repository — in
   the shapes `/veris/schema` names, or pick an owner already in the sandbox.
3. Post the files with that owner through `/veris/files` where the
   manual shows it, or through the vendor's own upload API where files are
   attachments — rows first, files second, as
   [../veris-reference/state.md](../veris-reference/state.md) lays out.
4. Read them back and check the SHA-256 in each row against the local file.
5. Ask the engineer, then `promote_sandbox`. This is the one place a
   command promotes, and only with a yes; `build` and `fix` never do. On the
   hosted tier, never here either — see below.
6. Write what is in the sandbox — owners, paths, hashes — into `.veris/NOTES.md`.

Hosted: this step opens with `create_sandbox` and closes with
`promote_sandbox`, and the tier forbids both. Operate on the session's twin —
rows through `/veris/data` and files through `/veris/files`, at the
`control_url` `.veris/session.md` names, checked by SHA-256 exactly as above.
Promotion is the engineer's, from the host: say so, with the owners, paths and
hashes to promote, and do not call it.

Rows-only state is cheap to seed per task and do not need this. Report
and stop: `build` or `fix` takes the task.

Ask before installing the binary or sending repository code anywhere new.
