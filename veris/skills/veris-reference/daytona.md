# Daytona: provider recipe for the hosted tier

Read [hosted.md](hosted.md) for tier selection, the receipt, project notes and cleanup
responsibilities. This file supplies the [Daytona](https://daytona.io) commands and
limits. `veris-daytona`, a separate executable, provisions the box on the twin
`veris up` made, puts the code in it, runs commands in it, and deletes it.

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
   Before the test command, capture the trace watermark as
   [hosted.md](hosted.md#the-receipt) describes, after provisioning and installation.
   Every `exec` runs from `workDir` with the trust variables exported in front of the
   command, and streams its output. The patch line is this tier's
   `--patch-bundled-cas`: it appends the gateway's certificate to the CA bundles the
   installed SDKs ship, so it runs after the install and before the tests. `--env
   KEY=VALUE` adds a variable for one command, `--cwd <dir>` runs elsewhere,
   `--timeout <seconds>` bounds it. The exit code is the command's own.
5. Read [the receipt](hosted.md#the-receipt). Only then decide what the run proved.
6. `veris-daytona teardown <daytonaSandboxId>` when the task is done, then
   `veris down`. Teardown deletes the box and leaves the twin, which is yours. Nothing
   deletes a provisioned box for you otherwise: it stops after 30 idle minutes, is
   deleted 60 minutes after it stops, and is destroyed 4 hours after creation whatever
   state it is in.

## Certificate failures

A certificate error against a twin's host after the patch line ran is a bundled CA
the patch does not know; use [troubleshooting.md](troubleshooting.md)'s over-mount
procedure inside the box with `exec`.

## Limitations

- Daytona allows 20 domains, and a large environment fills the list. The vendor
  hostnames, the gateway and the data planes are kept; package registries are trimmed
  from the tail, and `provision` prints what it dropped. Name the ones the install
  needs with `--allow-out`.
- `--strict` has no counterpart; the box uses Daytona's outbound domain allowlist.
  Package registries and any `--allow-out` hosts can also be reached.
- `teardown` needs the delete permission on the Daytona key. Without it, the refusal
  says when the box's own brakes take it; the box bills until then.
- `veris run`'s flags do not apply: `--environment`, `--fresh`, `--keep`, `--receipt`,
  `--expose`, `--strict`, `--patch-bundled-cas`. The run is not `veris run`, and the
  patch is the script line in step 4.
- Callbacks into the box are not wired by any verb here. A task that needs the app to
  receive webhooks belongs on the container tier.
- The image needs `curl`: the canary probe that proves the box reaches the twin uses
  it, and a slim image without it fails at `provision`.
