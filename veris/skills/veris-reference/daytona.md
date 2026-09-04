# Daytona: provider recipe for the hosted tier

Read [hosted.md](hosted.md) for tier selection, the receipt, project notes and cleanup
responsibilities. This file supplies the [Daytona](https://daytona.io) commands and
limits. `veris-daytona`, a separate executable, provisions the box on the twin
`veris up` made, puts the code in it, runs commands in it, and deletes it.

This is the CLI workflow. The separate `@veris-ai/daytona-opencode` package is loaded
by OpenCode to manage its sessions; its installation and sandbox ownership belong
to that plugin's workflow.

## What it needs

### Runner

Node 20 or newer is required. Use an exact published `@veris-ai/daytona` version:
reuse the version recorded in `.veris/NOTES.md`, or on first setup resolve the latest
release with `npm view @veris-ai/daytona@latest version` and record that concrete version.
Use it in place of `<version>` below; a moving tag such as `latest` does not belong
in the saved run commands.

Check `npm view @veris-ai/daytona@<version> version bin --json` first. The release
must export the `veris-daytona` executable. If it does not, stop before `veris up`
and report that a release containing the CLI is required. As checked on 2026-09-04,
the latest release, 0.2.1, has no `bin` entry or CLI file. This is a release
prerequisite; cloning or building an unreleased commit is not part of this recipe.

Once the release exports the executable, prefer version-pinned `npx`. Ask before
downloading a runner unless that is already authorized, then verify all four verbs:

```sh
npx --yes --package=@veris-ai/daytona@<version> veris-daytona provision --help
npx --yes --package=@veris-ai/daytona@<version> veris-daytona push --help
npx --yes --package=@veris-ai/daytona@<version> veris-daytona exec --help
npx --yes --package=@veris-ai/daytona@<version> veris-daytona teardown --help
```

For a one-off check of the latest release, the complete invocation is
`npx --yes --package=@veris-ai/daytona@latest veris-daytona provision --help`.
Omitting the version specifier can reuse a dependency already installed in the local
project. This recipe resolves latest once at setup, then uses the recorded version
for every command so a new release cannot change the runner midway through a task.

`npx` downloads into npm's cache as needed; it does not require a global installation.
Use the same version for every verb and record it in *How to run*. An existing global
installation is also usable once its version and four verbs have been checked.
If a required verb is absent, report the incompatible release before `veris up`.

The steps below use `veris-daytona` as shorthand. Replace it with the pinned `npx`
invocation you verified, including in the commands returned by `provision`. Record
the expanded commands so later sessions need no shell alias.

### Credentials

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

Done when the runner answers all four help commands, `DAYTONA_API_KEY` is set with
write and delete permissions, and Veris credentials are available through a source
that runner supports. Check these before bringing up the twin.

## The run

1. `veris up`, as in every tier. It writes the twin's id to `.veris/twin.local.yaml`
   under `sandbox:` as `id`, and `veris status` shows it. Everything below attaches to
   that twin; the twin's TTL is its own, and nothing here extends it.
2. Provision a box on it:
   ```
   veris-daytona provision --sandbox <twin-id> --image node:20-bookworm
   ```
   `--image` must be an image Daytona can pull, with the runtime, `curl` and a POSIX
   shell. A local Docker tag is not uploaded by this command. `--snapshot <name>`
   selects an existing Daytona snapshot instead; the two options are exclusive.
   With neither, Daytona chooses its default snapshot, whose runtime may differ from
   the project's. Choose the image before provisioning; see
   [hosted.md](hosted.md#prepare-the-remote-workload).
   `--allow-out <host>` adds a hostname the install needs beyond the package
   registries; the allowlist is fixed at create, so say it here. Read the GitHub
   limitation below before relying on a clone or runtime download.
   `--env KEY=VALUE` sets a literal variable on the box for
   every command run in it. Progress goes to stderr and one JSON object to stdout.
   Keep `daytonaSandboxId` from it; check `verisSandboxId` matches this task's twin.
   `workDir` is where the code will land, `services` names the twins, and
   `patchBundledCasCommand` names the script to run after installing dependencies.
   `pushCommand` and `execCommand` contain the box id; apply your verified runner
   prefix to them. Done when it exits 0 and the JSON names the expected twin.
3. `veris-daytona push <daytonaSandboxId>` uploads the current directory into
   `workDir`, minus `.git`, `node_modules`, `.venv`, `dist` and the rest that is rebuilt
   inside. Run it from the directory the test command needs, which may be a subdirectory
   of the repository. The upload uses the runner's exclusions, not `.gitignore`;
   inspect what else is in that directory before sending it. Include required files
   deliberately, using [hosted.md](hosted.md#prepare-the-remote-workload).
   `--repo <url> --ref <branch>` clones inside the box, but that path has a known
   GitHub routing limitation; use upload unless the target plane has been verified.
   A repeated upload overwrites matching files but leaves other remote files in place.
   If the change removes or renames files, remove the obsolete remote copies or use
   a fresh box before measuring the changed flow.
4. Run in the box, one command at a time:
   ```
   veris-daytona exec <daytonaSandboxId> -- <the install command>
   veris-daytona exec <daytonaSandboxId> -- sh /tmp/veris-patch-bundled-cas.sh
   ```
   The install can take several commands, including unpacking an uploaded runtime.
   Use `patchBundledCasCommand` from the provision JSON; the example shows its current
   value. Now capture the trace watermark on the controlling machine as
   [hosted.md](hosted.md#the-receipt) describes, then run the tests:
   ```
   veris-daytona exec <daytonaSandboxId> -- <the test command>
   ```
   For a credential folder inside the upload, set its path in the remote shell:
   `veris-daytona exec <daytonaSandboxId> -- sh -c 'export VERIS_KEYS_DIR="$PWD/veris-keys"; exec <the test command>'`.
   Use the variable the application already reads; keep credentials out of git.
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
  needs with `--allow-out`. Required hosts and explicit allowances take priority over
  registries; if those alone exceed 20, provisioning fails. Read any dropped-registry
  message before installing dependencies. An image with dependencies already installed
  avoids those downloads.
- `github.com` is intentionally absent from the default registry list. The earlier
  cloud-run trial found a gateway bug that could route it to an undeployed GitHub twin,
  so adding `--allow-out github.com` alone does not establish that clones or runtime
  downloads work. Upload from the controlling machine or use an image carrying the
  dependencies until the target plane has been verified. `codeload.github.com` and
  `raw.githubusercontent.com` are registry-list entries, subject to the same budget.
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
