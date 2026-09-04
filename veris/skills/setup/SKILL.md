---
name: setup
description: Wire this repository to Veris once - sign in, name the vendors the code calls, create the environment, build a test image, bring up a sandbox, and prove with one run that the code's own vendor calls reach the fake vendors. Run before build or fix. Run when the engineer names this command.
argument-hint: "[service names...]"
disable-model-invocation: true
---

Wire this repository to Veris, once. Re-running skips what is already done.

Three rules, always:

- Never modify the application code, and never point it at a sandbox. The one
  exception is the direct tier in step 3, where the app already reads each vendor's
  URL from an environment variable and production sets that same variable. Everywhere
  else, `veris run` redirects the app's traffic from outside the process, and the code
  keeps its production hostnames and credentials.
- Never print an API key. `veris` masks keys; keep it that way.
- Ask before creating an environment, installing anything, or promoting a sandbox.

Every command below is `veris`, and `veris <command> --help` lists its flags. You run
without a terminal, so every answer you mean to give has to be a flag. `--yes` confirms.
A command that would otherwise stop and ask refuses instead, and names the flag it needs.
Every `get` and `list` takes `--json`. `env get` and `env use` accept the shortened id a
table prints; `--from` needs the full id, which `--json` prints.

## 1. Check the machine

Run `veris doctor`. It prints one line per check, in this order: the binary's version,
login, control plane, gateway mode, the vendor hostnames the plane serves, Docker,
tunnel binary (cloudflared), certificate file, project file, environment, sandbox.

Some lines appear only when they apply. Gateway mode and the vendor hostnames need you
logged in and the plane answering, so on a fresh machine they are simply absent. The
environment line needs a project file. A live sandbox adds its clock and its callback
registration. A `VERIS_API_KEY` in your shell that overrides the profile's own key adds
a warning just after the login line.

`✓` passed, `!` worth knowing, `✗` will fail a run. Doctor changes nothing itself; a
`→` line names the command that would. It exits 1 when any check failed. `--json` puts
the same checks on stdout.

- `command not found`: `veris` is not installed, and nothing else here installs it. Ask
  the engineer, then run the line for their machine. macOS and Linux:

  ```sh
  curl -LsSf https://raw.githubusercontent.com/veris-ai/veris-cli/main/scripts/install.sh | sh
  ```

  Windows:

  ```powershell
  powershell -c "irm https://raw.githubusercontent.com/veris-ai/veris-cli/main/scripts/install.ps1 | iex"
  ```

  No root and no package manager are needed. On macOS and Linux the binary lands in
  `~/.local/bin`, so a second `command not found` means that directory is not on the
  PATH: say so and stop.
  Done when `veris doctor` prints its version line.
- `✗ Not logged in`: run `veris login`. It prints a pairing code and a console link.
  Show both to the engineer and tell them to approve the pairing in the browser. Then
  wait: the command finishes by itself once the pairing is approved, and saves the key
  under the profile. `--no-browser` prints the link without opening a browser. For
  another control plane: `veris login --profile dev --api-base <url>`. In CI nobody can
  approve a pairing, so `veris login --key-stdin` reads an existing key from stdin.
  `veris whoami` shows which key, organisation and plane a command would use.
- `!` about Docker: the container tier in step 3 runs the tests inside Docker, so
  Docker must be running. Ask the engineer to start it. Never fall back to running
  without `--image` for code under test.
- `!` about a missing project file or sandbox on a fresh repository is the expected
  state, not a problem.
- Any other `✗`: say which line and how to fix it, then stop.

## 2. Find what the code calls

Read the code, not the README: SDK imports, hostnames, base-URL settings. List every
vendor **hostname** on the tested path.

`veris services` is the catalog. It prints one line per twin: the twin's name, what it
stands in for, the variable its URL is handed to the app under, and the vendor
hostnames the proxy intercepts for it. The name is what `--services` takes.

A twin printed as `name (+issuer)` signs in through a family issuer, and the control
plane deploys that issuer with every sandbox holding the twin: google-calendar arrives
with google-identity. `--services` takes the bare name, and naming the issuer as well
changes nothing. So a sandbox holds twins the environment never named, and
`veris status` marks each one `+`. Neither the twin nor the mark is an error to fix.

A twin with no hostnames is not intercepted, for one of two reasons. It may be a data
plane: the app connects to it directly, using a URL the run hands to the app, instead
of having a hostname redirected. A database is the usual case. Or this control plane
serves no hostname for it yet. `veris doctor`'s vendor-hostnames line names every twin
in that state, and only postgres and yente belong there. List a data plane the app
itself needs as well — its own database, a self-hosted service — since a suite that
needs it fails without it.

Match hostnames, not vendors. A vendor may use several hosts, and a twin may cover only
some of them: Stripe's twin answers `api.stripe.com`, and the files and meter-events
hosts are not covered. Several twins may also answer the same hostname, as the three
Google twins all list `www.googleapis.com`. The sandbox routes those by path, so
include every twin whose paths the code calls.

A hostname with no twin is a limitation. Write it down in step 7, and do not mock it.

Names given with this command are the starting list. Show the engineer the final list
and ask before creating anything.

## 3. Pick the tier, then build the image

There are two ways to run the tests, and each one is called a tier. Decide which tier
before building anything, and decide it from the code, not from the engineer's answer.

Look at every vendor call on the tested path. If each one builds its URL from an
environment variable the app already reads, and production sets those same variables
with the real hostname only as the default, then setting those variables is the shipped
code path. No proxy is needed. That is the direct tier.

In the direct tier, go to
[../veris-reference/direct.md](../veris-reference/direct.md), do its gate and its
wiring, then rejoin here at step 7. Skip the rest of this step, and skip steps 5 and 6:
there is no image and no proving run. Step 4's environment rules still apply to the
environment that wiring makes, so read `veris env list --json` first and reuse one that
already has every service. Step 4's proxy flags do not apply.

One hardcoded vendor hostname, in the app or inside an SDK it calls, means the
container tier below. So does a vendor base URL the app registers that no twin
publishes an env hint for, unless no tested path reaches that base. In the direct tier
such a base keeps talking to the real vendor and nothing catches it. `veris services`
names the hint variable for every twin, and it needs no sandbox, so check for a
missing hint here, before anything is running.

The container tier is `veris run --image`: the tests run in a container with the proxy
beside it. It is the tier for code under test. It covers every runtime, and it is the
only tier that can patch an SDK's bundled certificates.

Use any image that runs the tests: the repository's own test image or a Dockerfile
stage, or a stock toolchain image with the repository mounted. Build it now; step 4
records its tag. Nothing Veris-specific goes in the image: no key, no certificate, no
proxy settings. If deriving the image took real work, keep it as `Dockerfile.veris` at
the root with a comment naming the build tag. If the tests cannot run in a container
at all, stop and tell the engineer. Done when `docker image inspect <tag>` succeeds.

## 4. Create the environment

```
veris env create <project-name> --services stripe,asana --ttl 60 \
  --command '<the smallest test command that calls a vendor>' \
  --image <tag> --require-service stripe --default
```

An unknown service name is refused and the catalog is printed. Take the name from
`veris services`.

The `--ttl 60` above is a choice, not a requirement. Leave `--ttl` out and none is
recorded, and the control plane applies its own default. A number outside what the
server allows is refused, and the refusal names the bounds.

`--boot`, `--snapshot`, `--data` and `--command` behave the same way: each is recorded
only when given, and nothing is written for the ones left out, so a sandbox boots the
bundle, seeds nothing, and `veris run` takes its command after `--`. Only the name and
`--services` (or `--from`) are required off a terminal, so pass a flag because you want
what it records, not to answer a question. The one pairing is `--boot snapshot`, which
is refused without `--snapshot ID|NAME`.

Before creating an environment, run `veris env list --json` and read the name and
services of every environment already on the server. **Adopt one only when it is this
project's: its services are exactly your list, or its server name is the project's.**
Then `veris env create <project-name> --from <full id>`, with the same remaining
flags. Otherwise create one named for the project, even when an existing environment
contains every service you need. A superset boots and bills twins the code never
calls, and another project's environment is shared with it: `env delete --server` and
`baseline promote` by either side land on both. When you adopt, the question you ask
before creating anything names the environment as the server does, with its id, and
says it is shared. `--from` and `--services` cannot be combined, so an adopted
environment keeps the server's service list and you cannot extend it here. Names are
not unique on the server, so say which id you used.

The name and services go to the server. Everything else is written to
`.veris/twin.yaml`, under the environment: the TTL if you gave one, boot source, data
files, the test command as `run.command`, and a `proxy:` block built from the proxy
flags:

```yaml
environments:
  <project-name>:
    proxy:
      image: <tag>
      require_service: [stripe]
```

Commit `.veris/twin.yaml`. `veris run` reads both settings from there, so the daily
command carries neither flag. `--require-callback`, `--expose <port>` and `--strict`
land in the same block.

Mounts, `-e` variables, `--patch-bundled-cas` and `--cap-add` have no key in the file.
They go in the `veris run` line you record in `.veris/NOTES.md` at step 7. Data files
are none unless `--data` names them. The command also adds `.veris/twin.local.yaml` to
`.gitignore`; that file is per-machine and is never committed. Done when `veris env get`
shows each setting, where it came from, and the server's record.

## 5. Bring up a sandbox

Run `veris up`. It creates a sandbox of the environment and remembers its id for this
folder at once. Then it waits until the control plane reports the sandbox ready and
every twin answers. It adds the environment's data files, and prints each twin's URL
and the variable that URL is handed to the app under. A twin the environment never
named is a sign-in issuer the platform added (step 2), and the line beside its hint
says so.

Done when it exits 0 and lists the twins. `veris status` shows the sandbox at any time:
its state, boot source and expiry, and every twin's status, env hint, URL and table
counts. A sandbox lives for its TTL, then disappears.

On failure, read the exit code. A sandbox that failed is exit 1, with the reason. A
sandbox still provisioning when the wait runs out is exit 4. That wait is five minutes
by default, and `--timeout 10m` gives more. Exit 4 keeps the sandbox and it may still
come up, so check `veris status` later. A data file the twin refused is exit 1 with the
sandbox kept: fix the file, then add it with `veris sandbox data add <file>`.

## 6. Prove it

```
veris run --patch-bundled-cas -- <the smallest test that calls the vendor>
```

Add what the command needs, the same way `docker run` would.

- `-v` to mount the repository where the image expects the code, when the image does
  not already contain it. `docker image inspect <tag>` names the image's WORKDIR.
- `-v <dir>:/run/keys:ro -e KEYS_DIR=/run/keys` for a credentials directory the app
  reads. Fill it with a made-up credential of the shape the twin accepts, rather than a
  real vendor key. That works unless the twin enforces its own published credentials;
  the paragraph on auth modes below says what to do then.
- `-e` for any variable the test expects.

Mount nothing but the repository, a dependency cache, or a credentials directory.

`--patch-bundled-cas` appends the proxy's certificate to every SDK-bundled CA file it
knows: certifi, botocore, stripe, httplib2. Stripe, botocore and httplib2 need it, and
it costs nothing when the image bundles none. `--receipt <file>` writes the receipt to
that file as JSON, and never to stdout.

The run prints two counts per twin:

```
veris: the sandbox received 6 request(s):          ← what the proxy saw leave the app
  stripe   6
veris: the sandbox recorded 6 request(s) since the watermark:   ← what the twin logged
  stripe   6
veris: ✓ required stripe ≥1: saw 6   ✓ ledgers agree (6 = 6)
```

Those two counts are the run's two ledgers. The counts, and the verdict line under
them, are the run's receipt.

**Done when both counts for the required twin are above zero and the run exits 0.**

Counts above zero are not enough on their own. If both counts are above zero but the
run failed, the call reached the twin and the twin refused it. Read the twin's auth
mode with `veris sandbox data get <twin> auth`. A `permissive` twin accepts any
credential well-formed for that vendor; an `enforced` twin accepts only one it
published. Read the twin's own Credentials section with
`veris sandbox services manual <twin> --raw`; it says where those published credentials
live. Then give the app a credential the twin takes, or prove the wiring with a twin
whose credential you have. Either way, it goes in step 7 under **Credentials and
versions**.

Then record the full command in `.veris/NOTES.md` at step 7. `twin.yaml` holds only the
image, the required twin and the command after `--`. Only a mount that produced a
receipt goes in *How to run*. So if a later task will need a mount this run did not use
— the repository over the image's baked copy, a fixture tree — prove that mount here
too.

The command and the required twin that finally went green may not be the ones step 4
recorded. If they are not, re-record them with
`veris env create <name> --from <full id> --force`. Carry every flag the entry already
has: the corrected `--command` and `--require-service`, plus the same `--image` and
`--default`, and the same `--ttl`, `--boot` and `--data` when the entry records them.
The entry is replaced, not merged, so a flag you leave out is dropped. Drop
`--require-service` and every later run stops asserting the twin, then passes green on
an empty receipt. Without `--from` the command would also create a second environment on
the server. Re-run `veris env get` afterwards and check step 4's done-when again.

Your own `veris sandbox` reads do not count toward a run's totals. A run sets a
watermark when it starts and counts only what the sandbox recorded after it. Any
`/veris/*` reads you make while the run is going appear on a separate
`control-plane (/veris/*)` line, marked not counted.

A check passes when either count meets it. When one side alone decided a `✓`, the line
says which: `(engine; …)` or `(sandbox ledger; …)`. Exit 4 means neither count could
settle a check, so the outcome is unknown. Run it again. If it repeats, check
`veris status` and report it.

If the exit code is 3, the code never reached the sandbox. Check, in order:

1. The test never calls the vendor: an in-process mock still active, a filter that
   skipped it. Pick a test that does.
2. The vendor's hostname is not one the environment's twins answer for: compare the
   code's hostnames with `veris services` and `veris env get`.
3. The SDK refused the certificate: `CERTIFICATE_VERIFY_FAILED`, `SSLError`, or a
   connection error against a vendor host. When a host rejected every handshake, the
   run prints a line naming the host and a `Next:` step. Follow it.
   `--patch-bundled-cas` fixes bundled CA files. A JVM client takes
   `--java-truststore`. An SDK that pins certificates cannot be patched: stop and
   report it. The full procedure is in
   [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md),
   **An SDK refuses the proxy's certificate**.
4. The twin is a data plane with no hostname, such as a database or a self-hosted
   service like Yente. Those are not proxied. The run hands the twin's URL to the app
   under the variable `veris up` printed for it, and says so:
   `veris: yente: not proxied; handed YENTE_API_BASE=…`. The app must read that
   variable, and a `-e` of your own for the same variable wins. Traffic to a data plane
   shows only in the sandbox's count, never in the proxy's, and the verdict says
   `(sandbox ledger; not proxied)`. That is expected.
5. The control plane serves no vendor hostname for an ordinary vendor twin. The run
   then hands that twin's URL to the app the same way, and prints the same `not proxied`
   line as item 4. Here that line is **not** expected. `veris doctor`'s vendor-hostnames
   line names every twin the plane serves no hostname for, and a vendor twin in that
   list is the cause. **Done when** doctor lists only data planes there, postgres and
   yente, or `--route <twin>=<host>` names the hostname for the run.
6. The app talks to the vendor from a process the run did not start (a compose
   sidecar): [../veris-reference/troubleshooting.md](../veris-reference/troubleshooting.md).

Never fix an exit 3 by changing the test's vendor call or its base URL.

## 7. Write down what you measured

Create `.veris/NOTES.md` and commit it. `build` and `fix` read it first, so anything a
later task would otherwise work out again goes here. Fill it from what you did: the
manual, the auth mode, and the proving run. The manual is
`veris sandbox services manual <twin> --raw`; `--raw` puts the markdown on stdout, and
without it the manual renders on stderr. The auth mode is
`veris sandbox data get <twin> auth`.

Use the headings below. Write *measured* or *not measured* under each one; an empty
heading is itself a finding. **Identity and matching** and **Errors and the dedup key**
are the exception. One happy-path run collapses nothing, and no manual describes record
identity, so *not measured* is the expected entry for both at setup. `build` or `fix`
fills them in on first use, with the reads in
[../veris-reference/twin.md](../veris-reference/twin.md).

- **How to run.** The full `veris run` line that produced the receipt, mounts and
  variables included. Real paths, not placeholders. For a mount from outside the
  repository, say what is in it and how to make one. Say how the app gets its
  credentials, and which image was used and how it is built. In the direct tier there
  is no `veris run` line. Record how the variables are set and from what, and record
  the trace entry that proved the first real call;
  [../veris-reference/direct.md](../veris-reference/direct.md) calls it *The trust
  anchor*.
- **What the twin cannot represent.** Hostnames without a twin, data-plane twins,
  anything the smoke could not exercise.
- **Identity and matching.** Which fields the vendor treats as the same record, and
  any normalizing, truncating or joining it does on the way.
- **Errors and the dedup key.** Which failures bind to an idempotency key and replay
  on reuse, and which leave the key free. A fix that retries is built on this answer.
- **Credentials and versions.** The key shape each twin accepts, the API version
  pinned, and anything a made-up value gets away with.
- **Where the repo's own tests do not reach the vendor.** Suites that mock in-process
  pass green with an empty receipt. In most repositories the vendor-facing tests cannot
  produce a receipt at all, so naming the one test that can is worth more than a
  paragraph about the ones that cannot.
- **Anything the twin got wrong.**

## 8. Files, only if the app works with them

Skip this step unless the app uploads or reads files: Drive, Dropbox, attachments.
State that is only rows is cheap to seed per task and does not need a baseline.

The app may work with files and still have nothing to seed — no fixtures, or no
credential the file-capable twin accepts. Write that under **What the twin cannot
represent** and move on: a half-seeded baseline is worse than none.

Otherwise seed the files once, so that every later sandbox starts with them. The steps
are in [../veris-reference/state.md](../veris-reference/state.md), **Files**. Read the
files back and check each row's SHA-256 against the local file. Ask the engineer, then
run `veris baseline promote`. It captures this folder's sandbox, pins it as the
environment's baseline, and deletes the source sandbox afterwards. `--keep-source`
keeps that sandbox instead, frozen and scrubbed. Promote is the last thing you do with
that sandbox. Done when `veris baseline get` shows the pin. Every later `veris up`
starts from that state, and this is the only place setup promotes. Write what is in the
sandbox into `.veris/NOTES.md`: owners, paths, hashes.

## 9. Stage the ledger scripts

`fix` keeps a ledger of what it measured, and checks that ledger against the diff. Two
scripts that ship in this plugin do the work. Copy `record.sh` and `ledger.sh` from
this plugin's `veris-reference/scripts/` directory into `.veris/bin/`; derive the
absolute path of that directory from the path of the file you are reading. Re-running
setup copies them again, which is how a stale copy is repaired.

`record.sh` reads three facts from `.veris/setup.json`, and `ledger.sh` reads none.
Write that file now, from the repository's own build definition and never from
memory:

```json
{"source_roots": ["api/app"], "build_command": "make build", "build_outputs": ["dist"]}
```

`source_roots` is where production source lives. `build_command` and `build_outputs`
are the repository's own build command and the directories that build writes. Without
them a later task cannot tell a fresh build from a stale one, and it says so rather
than pretend. If the tests run in a container image, `build_command` is the command
that builds that image and `build_outputs` is `[]`; put the image tag in
`.veris/NOTES.md`. An interpreted language often writes no build directory at all, and
`[]` is the honest answer there. Do not name a build that has nothing to do with the
code under test.

Append these two lines to `.gitignore` if they are not there already. Never ignore
`.veris/` as a whole: that would take `twin.yaml` and `NOTES.md` with it.

```gitignore
.veris/bin/
.veris/tasks/
```

Then ask the engineer once where a task's diagnosis, ledger, record and saved evidence
should go. Record the answer in `.veris/setup.json` as `artifact_policy`. There are
three answers:

- `pr-body`, the default: rendered into the change description.
- `local`: kept on disk only.
- `commit`: committed under `.veris/tasks/<task-id>/`.

Before the engineer chooses `commit`, say plainly that it merges into the default
branch and accumulates one directory per task. If they choose it anyway, drop the
`.veris/tasks/` line you just added to `.gitignore`.

## 10. Finish

`veris down --yes` deletes this folder's sandbox. After a promote in step 8 there is
none left to delete. Tell the engineer what to commit: `.veris/twin.yaml`,
`.veris/NOTES.md`, `.veris/setup.json`, and `Dockerfile.veris` if you wrote one. Report
the receipt line from step 6; in the direct tier, report the trace entry that stood in
for it. `build` or `fix` takes the task from here. Ask before sending repository code
anywhere new.
