# Running the tests in a cloud box

Read this when the engineer asks for the tests to run on a cloud machine: "run the
tests on Daytona". The ask is the only trigger. Do not check for Docker first. Someone
whose Docker works may still want a box, because their laptop is slow or the box
matches CI.

Only the test command moves. The twin is created on the engineer's machine with
`veris up` and stays there. Seeding rows, arming faults, moving the clock, reading the
trace, reading stored rows and tearing down all stay there too. The box cannot reach
the Veris control plane, so it cannot erase the record of what it sent.

The `veris` CLI does not change. It has no flag for a box.

There is no receipt, because no proxy of ours is in the path. The evidence is the
twin's trace. Take a watermark before the run, read the trace after it, and the
difference is what the run sent. [direct.md](direct.md) proves a run the same way.

## Before you bring anything up

- The provider's runner, and a machine that can run it.
- The provider's API key, in your environment. The provider half below names the
  variable and where to get one.

Check the key first. `veris up` before that check leaves a twin running and billing
while the engineer goes looking for a key.

Never print the key, never put it on a command line, and never write it into a file in
the repository. It travels as an environment variable and nothing else.

## The image is yours, and it is not the local one

The runner gives you an image and a directory to work in. It installs nothing, and it
puts no code in the box.

The provider builds and resolves images on its own servers, and it never sees your
Docker daemon. The container tier's test image ([run.md](run.md), *The image*) is
local, so naming it here fails.

An image that already carries the dependencies is the best fit. Nothing is installed
for you, and it needs no package registries at all.

A repository that needs a database, several services or a particular runtime standing
up around its tests does not fit. Bake those into the image, or run the tests locally.
Decide which of these the repository is before provisioning anything.

## The runtime the box does not have

The default box carries the provider's choice of language runtime, not yours. A
project pinned to an older one has to get that interpreter from somewhere, and the
box's allowlist is fixed when the box is created. A downloader that reaches a host
outside that list fails deep inside the install.

Two ways round it:

- put the interpreter in the image, which is what an image you build yourself is for;
- ship a standalone build of it with the code and unpack it before installing the
  dependencies.

The trial did the second. It shipped a 33 MB python-build-standalone tarball with the
code, unpacked it into `$HOME/py312` in 2 seconds, and installed the dependencies
against that interpreter in 9 more.

The interpreter is part of the install, so it goes in the same place in the order:
before the certificate patch.

## Getting credentials and paths into the box

There is no mount. The container tier's `-v` has no equivalent, and nothing on your
machine is visible from inside the box.

An application that reads its keys from a folder needs that folder inside the code that
goes up with it. The trial put the twin's credentials in `veris-keys/` at the root of
the directory it uploaded, and named the folder from inside the test command:

```sh
sh -c 'export VERIS_KEYS_DIR="$PWD/veris-keys"; exec ./.venv/bin/python -m smoke.smoke_stripe'
```

Use the twin's own credentials, never a real vendor key, and keep the folder out of
git.

A variable set on the box at create time cannot do that job. Those values are set
literally, so `$HOME` and `$PWD` inside one are never expanded. The box's absolute
paths are not knowable before it exists either. Set a path-valued variable inside the
command, where a shell expands it.

## 1. Bring the twin up here

Run `veris up`. Done when it exits 0 and lists the twins.

Its last lines name the twin, with the id in full:

```
✓ Up: 9rq751upj3p7gag6dlx88f5xn is this folder's sandbox (expires 11:04 EDT)
```

That id is the twin the box attaches to. `veris status` prints it again as its first
line.

It also ends with `→ Next: veris run`. Ignore that line here; it names the container
tier, which is the tier this page replaces.

## 2. Seed, arm and set the clock here

Do all of it before the run. Nothing in the box can do any of it.

```
veris sandbox data get <twin>                       # every table and its row count
veris sandbox data schema <twin> --table <t>        # the shape of a row
veris sandbox data add rows.json                    # rows, from a file keyed by twin
veris sandbox data set <twin> <table> id=<id> <field>=<value>
veris sandbox clock set --offset 31d                # or --freeze-at <RFC3339>, or --live
```

Row shapes are in [state.md](state.md). Fault rows go in the same `data add` file, and
[faults.md](faults.md) has them. Done when `veris sandbox data get <twin>` shows the
rows the flow needs.

## 3. Take a watermark

Take one per twin you mean to read afterwards. Trace ids are each twin's own sequence.

```
veris sandbox trace --service <twin> --limit 1 --json | jq '.[0].id // 0'
```

Keep the number. A freshly booted twin has no traffic at all, so the command prints
`[]` and the pipeline gives `0`. Read back with `--since 0`, which means everything.
Measured on the trial's twin before its first run.

## 4. Put the code in the box and run the tests

The provider half has the commands. Come back here afterwards.

The code goes in, then commands run in it one at a time, in this order: the install,
the certificate patch, then the tests. The patch comes after the install, because the
files it patches arrive with the dependencies. The install is as many commands as it
takes; the trial used two, one for the interpreter and one for the dependencies.

## 5. Read the evidence here

```
veris sandbox trace --service <twin> --since <watermark> --tier handler
veris sandbox data get <twin> <table>
veris sandbox trace --body <id> --service <twin>
```

The first is what the application sent. The second is what the twin stored. The third
prints one entry's request and response headers and bodies, for when a count is not
enough.

Nothing fails the run for you. The single-command runner this page used to teach read
the twin itself and exited non-zero when the tests passed and nothing arrived. No
command here passes a verdict. Make the check yourself: take the watermark before, read
the trace after, and an empty trace means the run proved nothing whatever the tests
printed.

`--tier` decides which traffic you see, and there are four:

| tier | what it holds |
|---|---|
| `handler` | the application's own calls: this is the run |
| `fault` | the exchange an armed fault produced |
| `control` | your own seeding and read-back, through `/veris/*` |
| `delivery` | callbacks the twin delivered |

Ask for `handler` when you mean the application. An unfiltered page after a heavy seed
is mostly `control`, and counting that as the app's traffic is how someone concludes
their code called a vendor when it did not.

`--limit` caps a page at 1000 rows, and the merge is newest first across twins. Ask per
twin, or a busy twin pushes a quiet one off the page.

## 6. What counts as worked

- The trace since the watermark shows the calls the tests were meant to make.
- The rows the twin stored are what the change promises.

Both, read back on the machine after the trial's smoke ran in the box:

```
  Time          Twin    Tier     Method  Path                                     Status  ms
  14:07:15.000  stripe  handler  DELETE  /v1/customers/cus_06a9ad09300001         200     59
  14:07:15.000  stripe  handler  POST    /v1/refunds                              200     96
  14:07:15.000  stripe  handler  POST    /v1/payment_intents                      200     189
  14:07:15.000  stripe  handler  POST    /v1/payment_methods/pm_card_visa/attach  200     104
  14:07:15.000  stripe  handler  POST    /v1/customers                            200     101
  14:07:15.000  stripe  handler  GET     /v1/balance                              200     381
```

Six requests, the six that smoke makes. `veris sandbox data get stripe refunds` then
showed the refund it created, `re_06a9ad093000106a3600c9e5`, against the payment intent
the trace names.

An empty trace means the run proved nothing, whatever the tests printed. Check three
things, in this order: the tests never called the vendor, the commands ran without the
trust environment, or they ran outside the working directory. Report the empty trace,
not the green.

## 7. Tear down both sides

- The box: the provider's teardown command below.
- The twin: `veris down --yes`.

When the run died before teardown, check both by hand. `veris sandbox list` shows the
twins of the in-use environment, and `veris down --all --yes` deletes them.
`veris status` says whether this folder still points at one. For the box, take the id
the provision JSON printed and tear it down by id; a box that is stopped still holds
its disk. Both sides expire on their own, but do not leave either to a timer.

## 8. Write the run line into NOTES.md

Put the whole sequence under *How to run* in `.veris/NOTES.md`: the provision line, the
line that put the code in, every command run in the box, and the teardown line. Real
ids and real paths, as with any other run line.

`build` and `fix` read their run line from that heading. Neither needs to know where
the tests ran.

## What the box cannot do

- Reach the Veris control plane. No `veris` command works from inside it.
- Receive callbacks. A suite that needs webhooks delivered to the application runs on
  your machine ([webhooks.md](webhooks.md)).
- Fail a run for you. There is no `--require-service`, no `--strict` and no exit 3. The
  trace is the only check, and you make it.
- Run Docker, or anything else the image does not already carry.
- Reach a hostname the allowlist did not get when the box was created. The list is
  fixed then, and the provider caps its length.

## Daytona

### The runner

The runner is `veris-daytona`, from the `@veris-ai/daytona` package. `npx -y
@veris-ai/daytona@<version> <verb>` runs it without installing anything. Pin the
version; `@latest` changes what a recorded run line does.

Four verbs do the whole job:

```
veris-daytona provision --sandbox <twin id>    # a wired box on a twin that exists
veris-daytona push <box id>                    # this directory into the box
veris-daytona exec <box id> -- <command>       # one command, trust environment applied
veris-daytona teardown <box id>                # delete the box, leave the twin
```

The trial ran studio-ops' Stripe smoke through them: 7 commands, 28 seconds of runner
time end to end, one box, 6 requests on the twin's trace afterwards.

No published version carries them yet. Measured: `npx -y @veris-ai/daytona@0.2.1
provision --help` fails with `could not determine executable to run`, because 0.2.1
publishes no executable at all. Check with `veris-daytona provision --help`, which
answers when the version has them. Until one does, this path needs a build of the
package's repository, and an engineer without one runs the tests locally
([run.md](run.md)).

### The Daytona key

This is a second key, beside `VERIS_API_KEY`. Veris does not store it, and
`veris doctor` has no line for it.

1. Get one from the Daytona dashboard's API keys page,
   https://app.daytona.io/dashboard/keys.
2. Ask the engineer to add one line to their shell startup file, the way
   `VERIS_API_KEY` is set for the MCP server today:

   ```sh
   export DAYTONA_API_KEY=<the key>
   ```

   They paste it, not you. Never into a file in the repository.
3. Check it is there without revealing it:

   ```sh
   [ -n "$DAYTONA_API_KEY" ] && echo set || echo missing
   ```

   Never echo the variable itself.
4. `missing` stops the work here, before `veris up`. The runner exits 2 with
   `DAYTONA_API_KEY is not set`, and a twin brought up first would bill while nobody
   uses it.

The runner reads `VERIS_API_KEY` from the environment too. `veris login` keeps its key
in a profile file, so a logged-in CLI is not enough on its own.

Export `VERIS_API_BASE` beside it whenever the twin is not on the production plane. The
runner defaults to `https://svc.api.veris.ai` and never reads the CLI's profile. A dev
key sent to production comes back as an authentication error that blames the key, and
the key is fine. The trial ran with:

```sh
export VERIS_API_BASE=https://svc.dev.api.veris.ai
```

`VERIS_ENVIRONMENT_ID` is not used: the environment comes from the twin.

Node 20 or newer runs the package.

### 1. Provision the box

```
veris-daytona provision --sandbox <twin id> > box.json
```

| flag | |
|---|---|
| `--sandbox <twin id>` | the twin to attach to, the id `veris up` printed. Required |
| `--image <name>` / `--snapshot <name>` | what the box runs; Daytona's default snapshot without either |
| `--allow-out <host>` | one more hostname the box may reach, repeatable |
| `--env KEY=VALUE` | a variable set on the box, repeatable. Not for keys |

What to name in `--image` is under *An image or a snapshot of your own* below, and what
`--allow-out` costs is under *The 20-hostname budget*. Read both before provisioning
with either.

It creates the box and stops. It uploads nothing, runs nothing and deletes nothing.
Exit 0 means the box is up and trusted; exit 2 means it is not. The trial's took 5
seconds and ended with the three lines that follow it:

```
» Ready. The sandbox is up, trusted, and running nothing
  put code in:   veris-daytona push 9b1baf14-bef8-4d0d-8854-c8ec7922d216
  run something: veris-daytona exec 9b1baf14-bef8-4d0d-8854-c8ec7922d216 -- <command>
  delete it:     veris-daytona teardown 9b1baf14-bef8-4d0d-8854-c8ec7922d216
```

One JSON object comes back on stdout, progress on stderr. The fields the next steps
need:

| field | what it is for |
|---|---|
| `daytonaSandboxId` | the box id `push`, `exec` and `teardown` all take |
| `verisSandboxId` | the twin. Check it is the one you brought up |
| `workDir` | where `push` puts the code and `exec` runs. Nothing to carry by hand |
| `pushCommand` | the `push` line, with the box id already in it |
| `execCommand` | the `exec` line, with the box id already in it |
| `patchBundledCasCommand` | run it in the box after installing dependencies |
| `trustEnv` / `trustPrelude` | the CA variables, for a process you start another way |
| `services` | the twin's service names |
| `expiresAt` | when Daytona destroys the box whatever it is doing |

The box lives 4 hours, stops after 30 idle minutes, and is deleted an hour after it
stops. Tear it down anyway; those are backstops. The twin's own TTL is whatever
`veris up` gave it, and provision does not move it.

### 2. Push the code in

```
veris-daytona push <box id>
```

It tars the current directory and unpacks it in `workDir`. Run it from the directory
the tests run in, which is not always the repository root. The trial pushed the
repository's `api/` directory, 32.3 MB with the interpreter tarball in it, in 3
seconds:

```
» Uploading /…/four-verb-trial/api
  32.3 MB after excluding .git, node_modules, .venv, venv, __pycache__, .pytest_cache,
  .mypy_cache, .ruff_cache, dist, build, target, .next, .turbo, coverage, .DS_Store
  unpacked into /home/daytona/veris-run
```

`--repo <url> --ref <branch>` clones instead of uploading. The clone runs inside the
box, so the git host must be on the allowlist `provision` fixed. That clone does not
work under Veris egress today, so upload.

Exit 0 means the code is in the box. Exit 1 means there is no such box under this key.

### 3. Run the commands

```
veris-daytona exec <box id> -- <command>
```

Install, patch, test, in that order. The trial ran four, taking 2, 9, 5 and 4 seconds:

```sh
veris-daytona exec $BOX -- sh -c 'mkdir -p "$HOME/py312" && tar xzf py312-linux-x86_64.tgz -C "$HOME/py312" --strip-components=1'
veris-daytona exec $BOX -- sh -c 'export UV_PROJECT_ENVIRONMENT="$PWD/.venv" UV_PYTHON_DOWNLOADS=never; uv sync --locked --no-dev --python "$HOME/py312/bin/python3.12"'
veris-daytona exec $BOX -- sh /tmp/veris-patch-bundled-cas.sh
veris-daytona exec $BOX -- sh -c 'export VERIS_KEYS_DIR="$PWD/veris-keys"; exec ./.venv/bin/python -m smoke.smoke_stripe'
```

Run the patch after the install. It appends the Veris CA to the CA files that SDKs ship
inside themselves, and those files arrive with the dependencies. Without it an SDK that
verifies against its own bundle fails on its first vendor call; stripe-python is the
measured case. It names every file it changed:

```
the Veris CA was appended to /home/daytona/veris-run/.venv/lib/python3.12/site-packages/stripe/data/ca-certificates.crt
7 bundled CA file(s) patched
```

Running it twice is safe. The second run in the trial said `no bundled CA file needed
patching — no SDK that ships its own is installed here, or they already trust the Veris
CA`. Read that line after the first run as a warning: it means the install had not put
the SDK there yet. Take the command from `patchBundledCasCommand` in the provision JSON
rather than typing the path.

| flag | |
|---|---|
| `--cwd <dir>` | run somewhere other than `workDir` |
| `--env KEY=VALUE` | set on top of the trust environment, repeatable |
| `--timeout <seconds>` | how long the command may run. Default 1800 |

`exec` applies the trust environment itself, which is why the verb exists. Daytona
overwrites `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE` and
`NODE_EXTRA_CA_CERTS` inside the box with its own CA file, and that file cannot verify
the gateway's certificates. `daytona exec` has no way to set a variable at all.

Output streams as it happens. The exit code is the command's own, 124 on `--timeout`,
1 when there is no such box, 2 on a usage error. Measured: `exec <box id> -- sh -c
'exit 7'` exits 7. Everything after `--` is the command, so its own flags stay its own.

Data-plane variables such as `DATABASE_URL` are already set on the box, so commands
inherit them.

Then go back to step 5 and read the trace on your machine.

### 4. Tear the box down

```
veris-daytona teardown <box id>
```

Exit 0 deletes the box. Exit 1 means there is no such box under this key. It returns in
under a second, and says which twin it left alone:

```
» Deleting the sandbox; twin 9rq751upj3p7gag6dlx88f5xn is yours and is left running
  deleted 9b1baf14-bef8-4d0d-8854-c8ec7922d216
```

The twin is yours, so `veris down --yes` is what deletes it. Keep `VERIS_API_KEY` set
for this command: without it teardown refuses rather than strand a twin.

### What the default box holds

Daytona's default box was `daytonaio/sandbox:0.8.0` at the time of the trial. Measured
in it: user `daytona`, uid 1001, `uv` 0.9.26, system Python 3.14.4, and no Python 3.12.

`uv` would download an older interpreter, but it fetches from `github.com`, which is
not on the allowlist. That exclusion is deliberate. It works around a bug of ours: the
gateway resolves the platform's whole route table, claims `github.com` for a GitHub
twin the environment never deployed, and then answers nothing. Putting the host back on
the allowlist does not help. The fix belongs in the gateway and is not shipped.

`codeload.github.com` and `raw.githubusercontent.com` are reachable. An install that
clones from `github.com` needs an image that already has what it would fetch.

### An image or a snapshot of your own

Daytona builds the image on its own servers and resolves its name against Docker Hub.
Measured: `--image studioops-api-test` failed in 6 seconds with
`pull access denied, repository does not exist or may require authorization`.

Choose in this order:

- a snapshot or image you already use with Daytona: name it and go;
- a Dockerfile and no snapshot: register the Dockerfile with Daytona once, then name
  the snapshot it made;
- neither: leave `--image` and `--snapshot` off and take Daytona's default box.

Registering a snapshot involves no third-party registry. Daytona's own SDK builds one
from a local Dockerfile: `Image.fromDockerfile(path)` reads the build context, and
`daytona.snapshot.create({ name, image })` uploads it to Daytona's object storage,
builds it there and registers it under the name. **Nobody has run this path yet.** Read
`@daytona/sdk`'s own docs before telling an engineer it works.

Whatever the image is, it needs `curl` and a POSIX shell. The CA install and the canary
probe use both, and a `python:3.12-slim`-style image fails at create with
`curl: not found`. veris-daytona's README says so under *Limitations*.

### The 20-hostname budget

Daytona accepts 20 domains and no more. The runner fills the required ones first, then
spends what is left on package registries, and prints what it had to drop.

The trial's seven-twin environment used all 20: 9 vendor hostnames, the gateway, the
twin's own host for `yente`, which has no vendor hostname of its own, and 9 registries.
It named the 8 registries it dropped:

```
veris: Daytona allows 20 domains and this twin's own hosts take most of them, so these
registries were left off: archive.ubuntu.com, security.ubuntu.com, proxy.golang.org,
sum.golang.org, crates.io, static.crates.io, index.crates.io, ghcr.io.
```

Read that line before the install runs. A dropped registry fails deep inside the
install and blames something else.

`--allow-out <host>` fits until the required hosts alone reach 20, and each one costs a
registry slot. Past 20 the runner refuses at create and lists what it wanted.

An image carrying its own dependencies needs no registry at all, so the trim line stops
mattering. Turning them off does not make room for more twins: a twin's hostnames are
never what gets trimmed. The option is `veris.allowRegistries: false` in the SDK; the
CLI has no flag for it.
