---
name: setup
description: Wire this repository to Veris once - sign in, name the vendors the code calls, create the environment, build a test image, bring up a sandbox, and prove with one run that the code's own vendor calls reach the fake vendors. Run before build or fix. Run when the engineer names this command.
argument-hint: "[service names...]"
disable-model-invocation: true
---

Wire this repository to Veris, once. Re-running skips what is already done.

Three rules, always:

- Never modify the application code, and never point it at a sandbox. `veris run`
  redirects its traffic from outside the process; the code keeps its production
  hostnames and credentials.
- Never print an API key. `veris` masks keys; keep it that way.
- Ask before creating an environment, installing anything, or promoting a sandbox.

Every command below is `veris`; `veris <command> --help` lists its flags. You run
without a terminal, so every answer is a flag: `--yes` for confirmations, and a
command that would otherwise ask refuses and names the flag it needs. Every `get` and
`list` takes `--json`. `env get` and `env use` accept the shortened id a table prints;
`--from` needs the full id from `--json`.

## 1. Check the machine

Run `veris doctor`. It prints one line per check: login, control plane, Docker,
tunnel binary (cloudflared), certificate file, project file, environment, sandbox.
`✓` passed, `!` worth knowing, `✗` will fail a run. It changes nothing; a `→` line
names the command that would. It exits 1 when any check failed. `--json` puts the
same checks on stdout.

- `✗ Not logged in`: run `veris login`. It prints a pairing code and a console link
  (`--no-browser` prints the link without opening a browser). Show both to the
  engineer, tell them to approve in the browser, and wait; the command finishes by
  itself once the pairing is approved and saves the key under the profile. For
  another control plane: `veris login --profile dev --api-base <url>`. In CI, where
  nobody can approve a pairing, `veris login --key-stdin` reads an existing key from
  stdin. `veris whoami` shows which key, organisation and plane a command would use.
- `!` about Docker: the container tier needs Docker running. Ask the engineer to
  start it. Never fall back to running without `--image` for code under test.
- `!` about a missing project file or sandbox on a fresh repository is the expected
  state, not a problem.
- Any other `✗`: say which line and how to fix it, then stop.

## 2. Find what the code calls

Read the code, not the README: SDK imports, hostnames, base-URL settings. List every
vendor **hostname** on the tested path. `veris services` is the catalog, one line per
twin: its name (what `--services` takes), what it stands in for, the variable its URL
is handed to the app under, and the vendor hostnames the proxy intercepts for it. A
twin with no hostnames is a data plane (a DSN handed to the app, not proxied). Match
hostnames, not vendors: a vendor may use several hosts and a twin may cover only some
(Stripe's twin answers `api.stripe.com`; the files and meter-events hosts are not
covered). A hostname with no twin is a limitation you write down in step 7; do not
mock it.

Names given with this command are the starting list. Show the engineer the final list
and ask before creating anything.

## 3. The test image

`veris run --image` runs the tests in a container with the proxy beside it. That is the
tier for code under test: it covers every runtime, and it is the only one that can
patch an SDK's bundled certificates.

Use any image that runs the tests: the repository's own test image or a Dockerfile
stage, or a stock toolchain image with the repository mounted. Build it now; step 4
records its tag. Nothing Veris-specific goes in the image: no key, no certificate, no
proxy settings. If deriving the image took real work, keep it as `Dockerfile.veris` at
the root with a comment naming the build tag. If the tests cannot run in a container
at all, stop and tell the engineer. Done when `docker image inspect <tag>` succeeds.

## 4. Create the environment

```
veris env create <project-name> --services stripe,asana --ttl 60 --boot bundle \
  --command '<the smallest test command that calls a vendor>' \
  --image <tag> --require-service stripe --default
```

An unknown service name is refused and the catalog is printed; take the name from
`veris services`. `veris env list` shows what already exists on the server. To reuse
one, take its full id from `veris env list --json` and run
`veris env create <name> --from <id>` with the same remaining flags. `--from` and
`--services` cannot be combined: an adopted environment keeps the server's service
list. So if an existing one lacks services the code calls, create a new one rather
than reusing it. Names are not unique on the server, so say which id you used.

The name and services go to the server. Everything else is written to
`.veris/twin.yaml` (commit it) under the environment: TTL, boot source, data files,
the test command as `run.command`, and a `proxy:` block from the proxy flags:

```yaml
environments:
  <project-name>:
    proxy:
      image: <tag>
      require_service: [stripe]
```

`veris run` reads both from there, so the daily command carries neither flag.
`--require-callback`, `--expose <port>` and `--strict` land in the same block. Mounts,
`-e` variables, `--patch-bundled-cas` and `--cap-add` have no key in the file: they go
in the `veris run` line you record in `.veris/NOTES.md` (step 7). Data files are none
unless `--data` names them. The command also adds `.veris/twin.local.yaml` to
`.gitignore` (per-machine; never committed). Done when `veris env get` shows each
setting, where it came from, and the server's record.

## 5. Bring up a sandbox

Run `veris up`. It creates a sandbox of the environment, remembers its id for this
folder at once, waits until the control plane reports it ready and every twin answers,
adds the environment's data files, and prints each twin's URL and the variable it is
handed under. Done when it exits 0 and lists the twins. `veris status` shows the
sandbox any time: state, boot source, expiry, and every twin's status, env hint, URL
and table counts. A sandbox lives for its TTL, then disappears.

On failure: a sandbox that failed is exit 1 with the reason. Still provisioning after
the budget (five minutes by default; `--timeout 10m` gives more) is exit 4; the
sandbox is kept and may still come up, so check `veris status` later. A data file the
twin refused is exit 1 with the sandbox kept; fix the file and add it with
`veris sandbox data add <file>`.

## 6. Prove it

```
veris run --patch-bundled-cas -- <the smallest test that calls the vendor>
```

Add what the command needs, the same way `docker run` would: `-v` to mount the
repository (`-v "$PWD:/work" -w /work`) when the image does not already contain it, a
credentials directory the app reads (`-v <dir>:/run/keys:ro -e KEYS_DIR=/run/keys`),
`-e` for any variable the test expects. Mounts stay under the repository, a dependency
cache, or a credentials directory. `--patch-bundled-cas` appends the proxy's
certificate to every SDK-bundled CA file it knows (certifi, botocore, stripe,
httplib2); it costs nothing when there is none, and Stripe, botocore and httplib2 need
it. `--receipt <file>` writes the receipt as JSON, both ledgers and the verdict, to
that file and never to stdout.

The run prints two counts per twin:

```
veris: the sandbox received 6 request(s):          ← what the proxy saw leave the app
  stripe   6
veris: the sandbox recorded 6 request(s) since the watermark:   ← what the twin logged
  stripe   6
veris: ✓ required stripe ≥1: saw 6   ✓ ledgers agree (6 = 6)
```

**Done when both counts for the required twin are above zero and the run exits 0.**
Then record the full command in `.veris/NOTES.md` (step 7); `twin.yaml` holds only the
image, the required twin and the command after `--`. Your own `veris sandbox` reads
never count: the sandbox's ledger lists them on a separate `control-plane (/veris/*)`
line marked not counted.

A check passes when either count meets it; a `✓` that one side alone decided says
which, `(engine; …)` or `(sandbox ledger; …)`. Exit 4 means the outcome is
indeterminate: neither count could settle a check. Run it again; if it repeats, check
`veris status` and report it.

If the exit code is 3, the code never reached the sandbox. Check, in order:

1. The test never calls the vendor: an in-process mock still active, a filter that
   skipped it. Pick a test that does.
2. The vendor's hostname is not one the environment's twins answer for: compare the
   code's hostnames with `veris services` and `veris env get`.
3. The SDK refused the certificate: `CERTIFICATE_VERIFY_FAILED`, `SSLError`, or a
   connection error against a vendor host. When a host rejected every handshake the
   run prints a line naming the host and a `Next:` step; follow it.
   `--patch-bundled-cas` fixes bundled CA files; a JVM client takes
   `--java-truststore`. An SDK that pins certificates cannot be patched: stop and
   report it. The full procedure is in
   [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md),
   **An SDK refuses the proxy's certificate**.
4. The twin is a data plane with no hostname (a database, a self-hosted service such
   as Yente). Those are not proxied: the run hands the twin's URL to the app under the
   variable `veris up` printed for it and says so
   (`veris: yente: not proxied; handed YENTE_API_BASE=…`). The app must read that
   variable; a `-e` of your own for it wins. Its traffic shows only in the sandbox's
   count, never in the proxy's, and the verdict says `(sandbox ledger; not proxied)`;
   that is expected.
5. The app talks to the vendor from a process the run did not start (a compose
   sidecar): [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md).

Never fix an exit 3 by changing the test's vendor call or its base URL.

## 7. Write down what you measured

Create `.veris/NOTES.md` (commit it). `build` and `fix` read it first, so anything a
later task would otherwise re-derive goes here. Fill it from what you did: the manual
(`veris sandbox services manual <twin> --raw`; without `--raw` it renders on stderr,
with it the markdown goes to stdout), the auth mode (`veris sandbox data get <twin>
auth`), and the proving run. Use these headings and write *measured* or *not
measured* under each; an empty heading is itself a finding:

- **How to run.** The full `veris run` line that produced the receipt, mounts and
  variables included; how the app gets its credentials; the image and how it is built.
- **What the twin cannot represent.** Hostnames without a twin, data-plane twins,
  anything the smoke could not exercise.
- **Identity and matching.** Which fields the vendor treats as the same record, and
  any normalizing, truncating or joining it does on the way.
- **Errors and the dedup key.** Which failures bind to an idempotency key and replay
  on reuse, and which leave the key free. A fix that retries is built on this answer.
- **Credentials and versions.** The key shape each twin accepts, the API version
  pinned, and anything a made-up value gets away with.
- **Where the repo's own tests do not reach the vendor.** Suites that mock
  in-process; they produce a green with an empty receipt. Most repositories' vendor-
  facing tests cannot produce a receipt at all; naming the one that can is worth more
  than a paragraph about the ones that cannot.
- **Anything the twin got wrong.**

## 8. Files, only if the app works with them

Skip this unless the app uploads or reads files (Drive, Dropbox, attachments). Rows-only
state is cheap to seed per task and does not need this. Otherwise, seed the files once
so every later sandbox starts with them: the steps are in
[../veris-reference/state.md](../veris-reference/state.md), **Files**. Read them back
and check each row's SHA-256 against the local file. Ask the engineer, then
`veris baseline promote`. It captures this folder's sandbox, pins it as the
environment's baseline, and deletes the source sandbox afterwards (`--keep-source`
keeps it, frozen and scrubbed). Promote is the last thing done with that sandbox.
Done when `veris baseline get` shows the pin. Every later `veris up` starts from that
state. This is the only place setup promotes. Write what is in the sandbox, owners,
paths, hashes, into `.veris/NOTES.md`.

## 9. Stage the ledger scripts

`fix` keeps a ledger of measurements and checks it against the diff with two scripts
that ship in this plugin. Copy `record.sh` and `ledger.sh` from this plugin's
`veris-reference/scripts/` directory (derive the absolute path from the path of the
file you are reading) into `.veris/bin/`. Re-running setup re-copies them, which is
how a stale copy is repaired.

They read three facts from `.veris/setup.json`; write it now, measured, not guessed:

```json
{"source_roots": ["api/app"], "build_command": "make build", "build_outputs": ["dist"]}
```

`source_roots` is where production source lives; `build_command` and `build_outputs`
are the repository's own build and the directories it writes. Without them a later
task cannot tell a fresh build from a stale one, and says so instead of pretending.

Append these to `.gitignore` if absent, as targeted lines, never a blanket `.veris/`,
which would take `twin.yaml` and `NOTES.md` with it:

```gitignore
.veris/bin/
.veris/tasks/
```

Then ask once where a task's diagnosis, ledger and record should go, and note the
answer in `.veris/setup.json` as `artifact_policy`: rendered into the change
description (`pr-body`, the default), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit`; say plainly that this merges into the default
branch and accumulates one directory per task, and drop the `.veris/tasks/` line above).

## 10. Finish

`veris down --yes` deletes this folder's sandbox (after a promote in step 8 there is
none left to delete). Tell the engineer what to commit: `.veris/twin.yaml`,
`.veris/NOTES.md`, `.veris/setup.json`, and `Dockerfile.veris` if written. Report the
receipt line from step 6. `build` or `fix` takes the task from here. Ask before
sending repository code anywhere new.

## If the app reads vendor URLs from the environment

Some apps read every vendor base URL from an environment variable, the same one
production sets, with the real hostname only as the default. For those, pointing the
variables at a sandbox is the shipped code path, and no proxy is needed:
[../veris-reference/direct.md](../veris-reference/direct.md). The gate is in the code,
not the claim: if any vendor call on the tested path builds its URL in a way the
variable cannot override, it is the container tier.
