# Daytona tier: the code runs in a hosted box wired to the twin

The container tier needs a Docker daemon, and a cloud dev box usually has none.
`veris doctor` says so on its Docker line: `! docker not on PATH — host tier works;
--image (container tier) will not`, or a daemon that does not answer. The host tier is
not a fallback for code under test, so without this tier such a machine has no path.

Here the tests run in a [Daytona](https://daytona.io) sandbox instead of a container.
The box's outbound proxy is the twin's gateway, so every call the code makes to a
vendor hostname is answered by the twin, from outside the process. The code stays
unmodified and keeps its production hostnames, credentials and client stack, exactly
as under `veris run`. What changes is the runner: `veris-daytona`, a separate
executable, provisions the box on the twin `veris up` made, puts the code in it, runs
commands in it, and deletes it.

## Choosing it

Decide from `veris doctor`, never from the code. The direct-tier gate in
[direct.md](direct.md) comes first, because it is about the code; when the code fails
that gate and doctor's Docker line is `!` and nobody can start a daemon here, this is
the tier. When Docker answers, the container tier is the tier, and this file does not
apply.

Two more doctor lines gate it. The gateway line must read `Gateway mode configured`:
the box routes through the plane's gateway, and a plane that prints `Gateway mode not
configured` cannot serve one. The login line stays as it is.

## What it needs

- `npm i -g @veris-ai/daytona` gives the `veris-daytona` executable. Ask before
  installing. `veris-daytona <verb> --help` documents each verb; read `provision`'s
  before the first run.
- `DAYTONA_API_KEY`, from [app.daytona.io/dashboard/keys](https://app.daytona.io/dashboard/keys),
  with the **write and delete** sandbox permissions. A key with write alone provisions
  boxes it can never delete: teardown is refused and the box lives until Daytona's own
  brakes take it. Ask the engineer for the key; never print it.
- `VERIS_API_KEY`, the same key `veris` uses. `veris-daytona` reads it from the
  environment. Versions whose `veris-daytona provision --help` names the CLI profile
  can instead read the `veris login` profile in `~/.veris/twin.yaml` when the variable
  is unset. Those versions select `VERIS_PROFILE`, then the global active profile.
  They do not read a project's `profile:` setting in `.veris/twin.yaml`: export
  `VERIS_PROFILE=<that profile>` for both CLIs when the project selects one. Profile
  support merged on main may not yet be on npm, so check the installed help. Older
  versions still need `VERIS_API_KEY` and, for another plane, `VERIS_API_BASE` matching
  `veris whoami`. When the key is exported, doctor's warning that the shell key
  overrides the profile is expected.

Done when `veris-daytona --version` prints a version, `DAYTONA_API_KEY` is set, and
Veris credentials are available through a source the installed version supports.

## The run

1. `veris up`, as in every tier. It writes the twin's id to `.veris/twin.local.yaml`
   under `sandbox:` as `id`, and `veris status` shows it. Everything below attaches to
   that twin; the twin's TTL is its own, and nothing here extends it.
2. Provision a box on it:
   ```
   veris-daytona provision --sandbox <twin-id> --image node:20-bookworm
   ```
   `--image` is any image that runs the tests and has `curl` and a POSIX shell; a
   stock toolchain image is enough, since the code arrives in the next step. Nothing
   Veris-specific goes in it. `--allow-out <host>` adds a hostname the install needs
   beyond the package registries, `github.com` for a git dependency; the allowlist is
   fixed at create, so say it here. `--env KEY=VALUE` sets a variable on the box for
   every command run in it. Progress goes to stderr and one JSON object to stdout.
   Keep `daytonaSandboxId` from it; `workDir` is where the code will land, and
   `services` names the twins. Done when it exits 0 and the JSON is on stdout.
3. `veris-daytona push <daytonaSandboxId>` uploads the current directory into
   `workDir`, minus `.git`, `node_modules`, `.venv`, `dist` and the rest that is rebuilt
   inside. `--repo <url> --ref <branch>` clones instead.
4. Run in the box, one command at a time:
   ```
   veris-daytona exec <daytonaSandboxId> -- <the install command>
   veris-daytona exec <daytonaSandboxId> -- sh /tmp/veris-patch-bundled-cas.sh
   veris-daytona exec <daytonaSandboxId> -- <the test command>
   ```
   Every `exec` runs from `workDir` with the trust variables exported in front of the
   command, and streams its output. The patch line is this tier's
   `--patch-bundled-cas`: it appends the gateway's certificate to the CA bundles the
   installed SDKs ship, so it runs after the install and before the tests. `--env
   KEY=VALUE` adds a variable for one command, `--cwd <dir>` runs elsewhere,
   `--timeout <seconds>` bounds it. The exit code is the command's own.
5. Read the receipt, below. Only then decide what the run proved.
6. `veris-daytona teardown <daytonaSandboxId>` when the task is done, then
   `veris down`. Teardown deletes the box and leaves the twin, which is yours. Nothing
   deletes a provisioned box for you otherwise: it stops after 30 idle minutes, is
   deleted 60 minutes after it stops, and is destroyed 4 hours after creation whatever
   state it is in.

## The receipt

There is no `veris run` here, so there is no receipt line, no two ledgers and no
`--require-service` verdict. The twin's trace is the receipt, the way it is in the
direct tier. Before the run, note the newest entry for the required twin:

```
veris sandbox trace --service <twin> --limit 1 --json
```

After it, `veris sandbox trace --service <twin> --since <id>` is what this run sent,
and `veris sandbox data get <twin> <table>` is what the twin stored. Trace ids are each
twin's own sequence, so the watermark is per twin.

Treat "the box received traffic" the way `veris run` treats its receipt. **Done when
the trace shows at least one entry from this run for the required twin.** No entries
means the run proved nothing, whatever the test command printed: the same finding as
an exit 3, and the causes are the same, in the same order —
[troubleshooting.md](troubleshooting.md), *An empty receipt, exit 3*. A certificate
error against a twin's host after the patch line ran is a bundled CA the patch does
not know; the fix is the same file's over-mount procedure, done inside the box with
`exec`. Never fix an empty trace by changing the call or its base URL.

## What goes in the files

`.veris/twin.yaml`: no `--image` on `veris env create`, so `proxy.image` stays unset;
the other proxy flags have no run to act on here, so leave them out too.

`.veris/NOTES.md`, under *How to run*: the `provision` line with its real image and
any `--allow-out`, the `push` line, the install command, the patch line and the test
command as `exec` lines, and the watermark read. Then the trace entry that proved the
first real call, with its id, which [direct.md](direct.md) calls *The trust anchor*.
`build` and `fix` take their run lines from here.

## Limitations

- Daytona allows 20 domains, and a large environment fills the list. The vendor
  hostnames, the gateway and the data planes are kept; package registries are trimmed
  from the tail, and `provision` prints what it dropped. Name the ones the install
  needs with `--allow-out`.
- No receipt line: the only ledger is the twin's trace, so a check `veris run` would
  settle from the proxy's own count is settled from the trace alone. `--strict` has no
  counterpart; a hostname no twin answers for is simply blocked by the allowlist.
- `teardown` needs the delete permission on the Daytona key. Without it, the refusal
  says when the box's own brakes take it; the box bills until then.
- `veris run`'s flags do not apply: `--environment`, `--fresh`, `--keep`, `--receipt`,
  `--expose`, `--strict`, `--patch-bundled-cas`. The run is not `veris run`, and the
  patch is the script line in step 4.
- Callbacks into the box are not wired by any verb here. A task that needs the app to
  receive webhooks belongs on the container tier.
- The image needs `curl`: the canary probe that proves the box reaches the twin uses
  it, and a slim image without it fails at `provision`.
