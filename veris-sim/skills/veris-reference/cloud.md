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

- Node 20 or newer, for the provider's runner.
- The provider's API key, in your environment. [Daytona](#daytona) below names the
  variable and where to get one.

Check the key first. `veris up` before that check leaves a twin running and billing
while the engineer goes looking for a key.

Never print the key, never put it on a command line, and never write it into a file in
the repository. It travels as an environment variable and nothing else.

## The image is yours, and it is not the local one

The runner gives you an image and a directory to work in. It installs nothing, and it
puts no code in the box.

Daytona builds the image on its own servers and resolves its name against Docker Hub.
It never sees your Docker daemon. The container tier's test image
([run.md](run.md), *The image*) is local, so naming it here fails. Measured:
`--image studioops-api-test` failed in 6 seconds with
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

An image that already carries the dependencies is the best fit here: nothing is
installed for you, and it needs no package registries at all. See
[The 20-hostname budget](#the-20-hostname-budget).

A repository that needs a database, several services or a particular runtime standing
up around its tests does not fit. Bake those into the image, or run the tests locally.
Decide which of these the repository is before provisioning anything.

## Getting credentials and paths into the box

There is no mount. The container tier's `-v` has no equivalent, and nothing on your
machine is visible from inside the box.

An application that reads its keys from a folder needs that folder inside the code that
goes up with it. The trial put the twin's credentials in `veris-keys/` at the
repository root and named the folder from inside the test command:

```sh
sh -c 'export VERIS_KEYS_DIR="$PWD/veris-keys"; exec ./.venv/bin/python -m smoke.smoke_stripe'
```

Use the twin's own credentials, never a real vendor key, and keep the folder out of
git.

`--env` cannot do that job. Its values are set literally, so `$HOME` and `$PWD` inside
one are never expanded. The box's absolute paths are not knowable before it exists
either. Set a path-valued variable inside the command, where a shell expands it.

## The interpreter the box does not have

Daytona's default box was `daytonaio/sandbox:0.8.0` at the time of the trial. Measured
in it: user `daytona`, uid 1001, `uv` 0.9.26, system Python 3.14.4, and no Python 3.12.

A project pinned to an older Python has to get that interpreter from somewhere. `uv`
downloads one, and it fetches from `github.com`, which is not on the allowlist. That
exclusion is deliberate. It works around a bug of ours: the gateway resolves the
platform's whole route table, claims `github.com` for a GitHub twin the environment
never deployed, and then answers nothing. Putting the host back on the allowlist does
not help. The fix belongs in the gateway and is not shipped.

Two ways round it meanwhile:

- put the interpreter in the image, which is what an image you build yourself is for;
- ship a python-build-standalone tarball with the code and unpack it before installing
  the dependencies.

The trial did the second. It unpacked the tarball into `$HOME/py312`, then ran
`uv sync --locked --no-dev --python "$PY"` with `UV_PYTHON_DOWNLOADS=never`, and the
install took 8 seconds.

## 1. Bring the twin up here

Run `veris up`. Done when it exits 0 and lists the twins.

It prints `Up: <sandbox id> is ready (expires …)`, with the id in full. That id is the
twin the box attaches to. `veris status` prints it again as its first line.

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

## 4. Run the tests in the box

The provider half has the commands. Come back here afterwards.

## 5. Read the evidence here

```
veris sandbox trace --service <twin> --since <watermark> --tier handler
veris sandbox data get <twin> <table>
veris sandbox trace --body <id> --service <twin>
```

The first is what the application sent. The second is what the twin stored. The third
prints one entry's request and response headers and bodies, for when a count is not
enough.

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

An empty trace means the run proved nothing, whatever the tests printed. Check three
things, in this order: the tests never called the vendor, the commands ran without the
trust variables, or they ran outside the working directory. Report the empty trace, not
the green.

## 7. Tear down both sides

- The box: the provider's teardown command below.
- The twin: `veris down --yes`.

When the run died before teardown, check both by hand. `veris sandbox list` shows the
twins of the in-use environment, and `veris down --all --yes` deletes them.
`veris status` says whether this folder still points at one. For the box, take the id
the provision JSON printed and tear it down by id; a box that is stopped still holds
its disk. Both sides expire on their own, but do not leave either to a timer.

## 8. Write the run line into NOTES.md

Put the whole sequence under *How to run* in `.veris/NOTES.md`: the provision line, how
the code got in, the install command, the patch command, the test command, and the
teardown line. Real ids and real paths, as with any other run line.

`build` and `fix` read their run line from that heading. Neither needs to know where
the tests ran.

## What the box cannot do

- Reach the Veris control plane. No `veris` command works from inside it.
- Receive callbacks. A suite that needs webhooks delivered to the application runs on
  your machine ([webhooks.md](webhooks.md)).
- Fail a run for you. There is no `--require-service`, no `--strict` and no exit 3. The
  trace is the only check, and you make it.
- Run Docker, or anything else the image does not already carry.
- Reach more than 20 hostnames. See [The 20-hostname budget](#the-20-hostname-budget).

## The 20-hostname budget

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

## Daytona

### Check the runner first

`provision` and `teardown` are not published yet. Check before promising anything:

```
npx -y @veris-ai/daytona@<version> provision --help
```

`could not determine executable to run`, or an unknown verb, means this path is not
available. Run the tests locally ([run.md](run.md)) and tell the engineer why.

Everything below is written from the package's source. Read `provision --help` when it
ships and follow that where the two differ.

### The runner

`npx -y @veris-ai/daytona@<version> <verb>` runs it without installing anything. Pin
the version; `@latest` changes what a recorded run line does. Installed globally, the
executable is `veris-daytona`.

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

### Provision the box

```
npx -y @veris-ai/daytona@<version> provision --sandbox <twin id> --image <image> > box.json
```

| flag | |
|---|---|
| `--sandbox <twin id>` | the twin to attach to, the id `veris up` printed. Required |
| `--image <name>` / `--snapshot <name>` | what the box runs; Daytona's default snapshot without either |
| `--allow-out <host>` | one more hostname the box may reach, repeatable |
| `--env KEY=VALUE` | a variable set on the box, repeatable. Not for keys |

It creates the box and stops. It uploads nothing, runs nothing and deletes nothing.
Exit 0 means the box is up and trusted; exit 2 means it is not.

One JSON object comes back on stdout, progress on stderr. The fields the next steps
need:

| field | what it is for |
|---|---|
| `daytonaSandboxId` | every command you run in the box, and `teardown` |
| `verisSandboxId` | the twin. Check it is the one you brought up |
| `workDir` | an empty directory in the box. Put the code there and run from there |
| `trustEnv` | the CA variables, as a map, for a process you start yourself |
| `trustPrelude` | the same variables as one line of shell `export`s |
| `patchBundledCasCommand` | run it in the box after installing dependencies |
| `services` | the twin's service names |
| `expiresAt` | when Daytona destroys the box whatever it is doing |

The box lives 4 hours, stops after 30 idle minutes, and is deleted an hour after it
stops. Tear it down anyway; those are backstops. The twin's own TTL is whatever
`veris up` gave it, and provision does not move it.

`github.com` is not reachable from the box. `codeload.github.com` and
`raw.githubusercontent.com` are. An install that clones from `github.com` needs an
image that already has what it would fetch.

### Put the code in, and run the commands

Both are yours to do, with Daytona's own CLI or SDK against `daytonaSandboxId`.
`daytona ssh <daytonaSandboxId>` opens a shell in the box.

Every command has to meet two conditions:

- it runs in `workDir`;
- it carries `trustPrelude` in front of it, or `trustEnv` in its environment. A command
  started without them inherits Daytona's own CA variables, and every vendor call fails
  on the certificate.

Data-plane variables such as `DATABASE_URL` are already set on the box, so commands
inherit them.

Then three commands, in this order:

```sh
<the install command>                 # npm ci, pip install -e ., uv sync
sh /tmp/veris-patch-bundled-cas.sh    # patchBundledCasCommand from the JSON
<the test command>
```

Run the patch after the install. It appends the Veris CA to the CA files that SDKs ship
inside themselves, and those files arrive with the dependencies. Without it an SDK that
verifies against its own bundle fails on its first vendor call; stripe-python is the
measured case. Running the patch twice is safe.

Then go back to step 5 and read the trace on your machine.

### Tear the box down

```
npx -y @veris-ai/daytona@<version> teardown <daytonaSandboxId>
```

Exit 0 deletes the box. Exit 1 means there is no such box under this key. The twin is
yours, so teardown leaves it running, and `veris down --yes` is what deletes it. Keep
`VERIS_API_KEY` set for this command: without it teardown refuses rather than strand a
twin.
