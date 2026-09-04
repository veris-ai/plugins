---
name: setup
description: Wire this repository to Veris once - sign in, name the vendors the code calls, create the environment, build a test image, bring up a sandbox, and prove with one run that the code's own vendor calls reach the fake vendors. Run before build or fix. Run when the engineer names this command.
argument-hint: "[service names...]"
disable-model-invocation: true
---

Wire this repository to Veris, once. Re-running skips what is already done.

Three rules, always:

- Never modify the application code, and never point it at a sandbox — except in the
  direct tier (step 3), where the variable that points it there is the one production
  sets. `veris run` redirects its traffic from outside the process; the code keeps its
  production hostnames and credentials.
- Never print an API key. `veris` masks keys; keep it that way.
- Ask before creating an environment, installing anything, or promoting a sandbox.

Every command below is `veris`; `veris <command> --help` lists its flags. You run
without a terminal, so every answer is a flag: `--yes` for confirmations, and a
command that would otherwise ask refuses and names the flag it needs. Every `get` and
`list` takes `--json`. `env get` and `env use` accept the shortened id a table prints;
`--from` needs the full id from `--json`.

## 1. Check the machine

Run `veris doctor`. It prints one line per check, in this order: the binary's version,
login, control plane, gateway mode, the vendor hostnames the plane serves, Docker,
tunnel binary (cloudflared), certificate file, project file, environment, sandbox.
Some appear only when they apply: gateway mode and the vendor hostnames need you
logged in and the plane answering, so on a fresh machine they are simply absent; the
environment line needs a project file; a live sandbox adds its clock and its callback
registration; and a `VERIS_API_KEY` in your shell that overrides the profile's own key
adds a warning just after the login line. `✓` passed, `!` worth knowing, `✗` will fail
a run. It changes nothing; a `→` line names the command that would. It exits 1 when
any check failed. `--json` puts the same checks on stdout.

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
twin with no hostnames is not intercepted. It is either a data plane (a DSN handed to
the app) or a twin this control plane serves no hostname for yet; `veris doctor`'s
vendor-hostnames line names every twin in that state, and only postgres and yente
belong there. List a data plane the app itself needs — its own database, a
self-hosted service — as well, since a suite that needs it fails without it. Match
hostnames, not vendors: a vendor may use several hosts and a twin may cover only some
(Stripe's twin answers `api.stripe.com`; the files and meter-events hosts are not
covered). Several twins may also answer the same hostname — three Google twins all
list `www.googleapis.com` — and the sandbox routes those by path, so include every
twin whose paths the code calls. A hostname with no twin is a limitation you write
down in step 7; do not mock it.

Names given with this command are the starting list. Show the engineer the final list
and ask before creating anything.

## 3. Pick the tier, then build the image

Decide this before building anything, and decide it in the code, not from the
engineer's answer. If every vendor call on the tested path builds its URL from an
environment variable the app already reads — the same variables production sets, the
real hostname only as the default — then setting those variables is the shipped code
path and no proxy is needed. That is the direct tier: go to
[../veris-reference/direct.md](../veris-reference/direct.md), do its gate and its
wiring, then rejoin here at step 7. Skip the rest of this step and steps 5 and 6 —
there is no image and no proving run. Step 4's environment rules still apply to the
environment its wiring makes: read `veris env list --json` first and reuse one that
already has every service. The proxy flags there do not.

One hardcoded vendor hostname, in the app or inside an SDK it calls, means the
container tier below. So does a vendor base the app registers that no twin publishes
an env hint for, unless no tested path reaches it: in the direct tier such a base
keeps talking to the real vendor and nothing catches it. `veris services` names the
hint variable for every twin and needs no sandbox, so this half can be checked here.

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
`veris services`. Before creating one, run `veris env list --json` and read the
services of every environment already on the server. **If one of them already has
every service on your list, adopt it rather than creating a second:**
`veris env create <name> --from <full id>` with the same remaining flags. Create a new
environment only when none of them has them all — `--from` and `--services` cannot be
combined, so an adopted environment keeps the server's service list and cannot be
extended here. Names are not unique on the server, so say which id you used.

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
repository where the image expects the code (`docker image inspect <tag>` names its
WORKDIR) when the image does not already contain it, a credentials directory the app
reads (`-v <dir>:/run/keys:ro -e KEYS_DIR=/run/keys`; a made-up credential of the
shape the twin accepts is normally enough, and safer than a real vendor key), `-e` for
any variable the test expects. Mounts stay under the
repository, a dependency cache, or a credentials directory. `--patch-bundled-cas`
appends the proxy's certificate to every SDK-bundled CA file it knows (certifi,
botocore, stripe, httplib2); it costs nothing when there is none, and Stripe, botocore
and httplib2 need it. `--receipt <file>` writes the receipt as JSON, both ledgers and
the verdict, to that file and never to stdout.

The run prints two counts per twin:

```
veris: the sandbox received 6 request(s):          ← what the proxy saw leave the app
  stripe   6
veris: the sandbox recorded 6 request(s) since the watermark:   ← what the twin logged
  stripe   6
veris: ✓ required stripe ≥1: saw 6   ✓ ledgers agree (6 = 6)
```

**Done when both counts for the required twin are above zero and the run exits 0.**

Counts above zero are not enough on their own. If both are above zero but the run
failed, the call reached the twin and the twin refused it. Read the mode
(`veris sandbox data get <twin> auth`) and the twin's own Credentials section
(`veris sandbox services manual <twin> --raw`), which says where its published
credentials live: `permissive` accepts any credential well-formed for that vendor,
`enforced` only a published one. Give the app a credential the twin takes, or prove
the wiring with a twin whose credential you have. Either way it goes in step 7 under
**Credentials and versions**.

Then record the full command in `.veris/NOTES.md` (step 7); `twin.yaml` holds only the
image, the required twin and the command after `--`. Only a mount that produced a
receipt goes in *How to run*, so if a later task will need one this run did not — the
repository over the image's baked copy, a fixture tree — prove it here too.

If the command or the required twin that finally went green is not the one step 4
recorded, re-record it with `veris env create <name> --from <full id> --force`,
carrying every flag the entry already has: the corrected `--command` and
`--require-service`, plus the same `--ttl`, `--boot`, `--image`, `--data` and
`--default`. The entry is replaced, not merged, so a flag you leave out is dropped —
and a dropped `--require-service` means every later run stops asserting the twin and
passes green on an empty receipt. Without `--from` the command would also create a
second environment on the server. Re-run `veris env get` afterwards to check step 4's
done-when again.

Your own `veris sandbox` reads do not count toward a run's totals: the counts are
taken since a watermark the run sets, and any `/veris/*` reads that fall inside the
run appear on a separate `control-plane (/veris/*)` line marked not counted.

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
5. The control plane serves no vendor hostname for an ordinary vendor twin, so it was
   handed over instead of intercepted and prints the same `not proxied` line as item
   4 — that one is **not** expected. `veris doctor`'s vendor-hostnames line names every
   twin the plane serves none for; a vendor twin there is the cause. **Done when**
   doctor lists only data planes (postgres, yente) there, or `--route <twin>=<host>`
   names the hostname for the run.
6. The app talks to the vendor from a process the run did not start (a compose
   sidecar): [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md).

Never fix an exit 3 by changing the test's vendor call or its base URL.

## 7. Write down what you measured

Create `.veris/NOTES.md` (commit it). `build` and `fix` read it first, so anything a
later task would otherwise re-derive goes here. Fill it from what you did: the manual
(`veris sandbox services manual <twin> --raw`; without `--raw` it renders on stderr,
with it the markdown goes to stdout), the auth mode (`veris sandbox data get <twin>
auth`), and the proving run. Use these headings and write *measured* or *not measured*
under each; an empty heading is itself a finding. **Identity and matching** and
**Errors and the dedup key** are the exception: one happy-path run collapses nothing
and no manual describes record identity, so *not measured* is the expected entry at
setup, and `build` or `fix` fills it on first use with the reads in
[../veris-reference/twin.md](../veris-reference/twin.md).

- **How to run.** The full `veris run` line that produced the receipt, mounts and
  variables included — real paths, not placeholders, and for a mount from outside the
  repository, what is in it and how to make one; how the app gets its credentials; the
  image and how it is built. In the direct tier there is no `veris run` line: record
  how the variables are set and from what, and the trace entry that proved the first
  real call ([../veris-reference/direct.md](../veris-reference/direct.md), *The trust
  anchor*).
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

Skip this unless the app uploads or reads files (Drive, Dropbox, attachments).
Rows-only state is cheap to seed per task and does not need this. If the app does work
with files but there is nothing to seed — no fixtures, or no credential the
file-capable twin accepts — write that under **What the twin cannot represent** and
move on; a half-seeded baseline is worse than none. Otherwise, seed the files once so
every later sandbox starts with them: the steps are in
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

`record.sh` reads three facts from `.veris/setup.json` (`ledger.sh` reads none); write
it now from the repository's own build definition, never from memory:

```json
{"source_roots": ["api/app"], "build_command": "make build", "build_outputs": ["dist"]}
```

`source_roots` is where production source lives; `build_command` and `build_outputs`
are the repository's own build and the directories it writes. Without them a later
task cannot tell a fresh build from a stale one, and says so instead of pretending. If
the tests run in a container image, `build_command` is that image build and
`build_outputs` is `[]`; put the tag in `.veris/NOTES.md`. An interpreted language
often writes no build directory at all, and `[]` is the honest answer there — do not
name a build that has nothing to do with the code under test.

Append these to `.gitignore` if absent, as targeted lines, never a blanket `.veris/`,
which would take `twin.yaml` and `NOTES.md` with it:

```gitignore
.veris/bin/
.veris/tasks/
```

Then ask once where a task's diagnosis, ledger, record and saved evidence should go,
and note the answer in `.veris/setup.json` as `artifact_policy`: rendered into the change
description (`pr-body`, the default), kept on disk only (`local`), or committed under
`.veris/tasks/<task-id>/` (`commit`; say plainly that this merges into the default
branch and accumulates one directory per task, and drop the `.veris/tasks/` line above).

## 10. Finish

`veris down --yes` deletes this folder's sandbox (after a promote in step 8 there is
none left to delete). Tell the engineer what to commit: `.veris/twin.yaml`,
`.veris/NOTES.md`, `.veris/setup.json`, and `Dockerfile.veris` if written. Report the
receipt line from step 6, or in the direct tier the trace entry that stood in for it.
`build` or `fix` takes the task from here. Ask before
sending repository code anywhere new.
