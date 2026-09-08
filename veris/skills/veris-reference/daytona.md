# Daytona: provider recipe for the hosted tier

Read [hosted.md](hosted.md) for tier selection, workload preparation, the trace
as receipt, project notes and cleanup ownership. This recipe uses the published
[@veris-ai/daytona SDK](https://www.npmjs.com/package/@veris-ai/daytona) from
[veris-daytona](https://github.com/veris-ai/veris-daytona), a drop-in for
`@daytona/sdk`, to manage a separate application-test box attached to the
task's existing twin. Like the [E2B recipe](e2b.md), it is the SDK used as
is, from a script the agent writes; the package ships no command-line tool. OpenCode provider configuration and
session-owned sandboxes belong to [session.md](session.md).

## Prerequisites and the release

The controlling machine needs Node 20 or newer, npm, tar and a working `veris`
installation. Check the credentials and gateway requirements below before
creating resources.

Reuse the exact SDK version in `.veris/NOTES.md`. On first setup, resolve
latest once and record the concrete result, then use that version for the
entire task:

```sh
npm view @veris-ai/daytona@latest version
# Put the returned concrete version in <version> for all following commands.
npm view @veris-ai/daytona@<version> version peerDependencies exports --json
```

The recipe needs, at least, **0.3.1**: `veris.attachSandboxId` on `create()`,
the gateway address pin (`networkAllowList`, never a `domainAllowList`, which
turns on Daytona's TLS inspection and ends every vendor call in a 502),
`receiptBaseline()` / `receiptSince()`, `getTrustEnv()`, `patchBundledCas()`
and the Node proxy preload described under *Proxy and trust*. 0.3.0 lacks the
preload and 0.2.1 lacks all of it; if `latest` is older, stop and report the
release prerequisite. Do not clone or build unreleased code to fill the gap.

Create a local runner directory, excluded from git and from the workload
upload. `@daytona/sdk` is a peer dependency and is installed beside it:

```sh
mkdir -p .veris/daytona
cd .veris/daytona
npm init -y
npm install --save-exact --ignore-scripts @veris-ai/daytona@<version> @daytona/sdk
npm ls @veris-ai/daytona @daytona/sdk
node --input-type=module -e 'import { Daytona, SDK_VERSION } from "@veris-ai/daytona"; console.log(SDK_VERSION, typeof Daytona)'
```

Keep this runner's `package.json` and `package-lock.json` for the task and
restore it with `npm ci --ignore-scripts`. Record both resolved versions in
*How to run*.

### Credentials and gateway

- `DAYTONA_API_KEY`, from [app.daytona.io/dashboard/keys](https://app.daytona.io/dashboard/keys),
  with the **write and delete** sandbox permissions. A key with write alone
  provisions boxes it can never delete. Ask the engineer for the key; never
  print it.
- `VERIS_API_KEY` **must be the same key, or a key of the same organisation,
  as the controlling `veris` CLI uses.** A twin is visible only to its
  organisation: with the CLI on one profile and the SDK on another key, the
  attach fails with `attach target <id> not found`, a 404 for a twin the CLI
  just created. Export the key the CLI uses, or leave the variable unset so
  the SDK reads the CLI's profile (`VERIS_PROFILE` selects one).
- `VERIS_API_BASE` set to the plane `veris whoami` names when it is not
  production. Leave `VERIS_ENVIRONMENT_ID` unset: attachment derives the
  environment from the twin.
- `veris doctor` must print `Gateway mode configured`. A plane that prints
  `Gateway mode not configured` cannot serve a hosted box.

### Image and runtime

`create()` takes Daytona's default snapshot when nothing is passed: Ubuntu, a
non-root `daytona` user with passwordless sudo, Node (25 as of 2026-09-08),
Python, `curl`, `tar`, `update-ca-certificates`. Pass `image: 'node:20-bookworm'`
for a specific runtime; Daytona builds a snapshot from any public image, which
takes a minute the first time, and such an image runs as root. The image needs
`curl` and a POSIX shell: the canary that proves the box reaches the twin uses
them, and a slim image fails at `create()`. Record the runtime versions the
box actually has (`node --version` inside it), not the ones the image name
suggests.

The default box is small: 3 GB of disk and a shared CPU. A JavaScript
application with a large dependency tree fits; a monorepo does not. It stops
after 30 idle minutes, is deleted 60 minutes after stopping, and is destroyed
4 hours after creation whatever state it is in. The twin's TTL is separate
and is not extended by anything here.

## Attach, upload and run

From the project root, `veris up`, or reuse the task's running twin.
`veris status` and `.veris/twin.local.yaml`'s `sandbox.id` identify it.
Export `VERIS_TWIN_ID=<that-id>` in the controlling shell. This is the twin's
id, not the Daytona box id.

Prepare a reviewed staging directory with the application source, lockfiles,
tests and only the twin credential files it needs. The script below tars it
with `COPYFILE_DISABLE=1` and leaves out `.git`, `node_modules`, `dist`,
`.venv` and their kin; nothing else is excluded, so review what is in the
directory. On macOS, without `COPYFILE_DISABLE` the archive carries
AppleDouble `._*` twins of every file, and a tool that globs a directory (a
migration runner did) tries to compile them. For a package inside a
workspace, stage a copy of the package plus the root config files it extends:
`npm install` inside a yarn or npm workspace resolves the whole monorepo and
fails on root-only conflicts.

The run is a sequence of SDK calls, made from a task-local Node script in
`.veris/daytona/` that the agent writes for this repository. There is no
command-line tool in the package and none to build: the installed package
documents its surface (`node_modules/@veris-ai/daytona/README.md` is the
manual, `dist/index.d.ts` the exact signatures), and the script is whatever
shape the task needs, as long as it makes these calls in this order and keeps
the box id in a state file so later invocations reattach instead of creating
a second box.

1. **Attach a box to the twin, once.** `new Daytona({ apiKey })`, then
   `daytona.create({ image?, veris: { attachSandboxId: twinId } })`. Save
   `sbx.id` at once (it is the only way back to the box) and check
   `sbx.verisSandboxId` is this task's twin; delete the box if it is not.
   Every later invocation reattaches with `daytona.get(savedId)`, which
   rehydrates the Veris surface from the box's labels.
2. **Put the code in.** Tar the staging directory on the controlling machine
   (`COPYFILE_DISABLE=1`, excluding `.git`, `node_modules`, `dist`, `.venv`,
   `._*`), `sbx.fs.uploadFile(localTgz, remotePath)`, then unpack it with
   `sbx.process.executeCommand('tar -xzf …')` into a work directory under
   the box's `$HOME`. Repeat after every local edit; a file removed locally
   stays in the box, so remove it there or use a fresh box before measuring
   a change that removes files.
3. **Install, then patch bundled CAs.** `sbx.process.executeCommand(install,
   workDir, sbx.veris.getTrustEnv(), timeoutSeconds)`, then
   `await sbx.veris.patchBundledCas()`. Repeat the patch after any later
   install; it is idempotent.
4. **Take the watermarks.** `const baseline = await sbx.veris.receiptBaseline()`
   in the script, and on the controlling machine, in the project root,
   `veris sandbox trace --service <twin> --limit 1 --json` for each required
   twin, as [hosted.md](hosted.md#the-receipt) says.
5. **Run the flow.** `sbx.process.executeCommand(testCommand, workDir, env,
   timeoutSeconds)` with `env` built from `sbx.veris.getTrustEnv()` plus what
   the application reads (its vendor credential from the twin's manual, never
   the real one), and a caller's `NODE_OPTIONS` passed through
   `verisNodeOptions()`. The result carries `exitCode` and `result`; output
   arrives when the command ends, not as it streams, so a long install shows
   nothing until it finishes. Exit the script with the command's own code.
6. **Read the receipt.** `await sbx.veris.receiptSince(baseline)` for what
   the twin received from this run, `sbx.veris.assertTouched(service, match?)`
   when the run must have reached a twin, and the CLI's
   `veris sandbox trace --service <twin> --since <watermark>` for tiers and
   bodies, which is what the ledger snapshots.
7. **Delete the box** with `sbx.delete()` when the task is done; the attached
   twin is left running, and `veris down` takes it.

Also on the surface: `sbx.veris.services()` and `manual(service)`,
`getDataPlaneEnv()`, `trustPrelude()` for a command line you can only prefix,
`deliverTo(port)` for callbacks, and the exported constants (`VERIS_BUNDLE`,
`NODE_PROXY_PRELOAD`, `BUNDLED_CA_PATCH_SCRIPT`). Record the script's exact
invocations, with the real install and test commands and the `env` the
application needed, in *How to run*.

Read [the shared receipt rule](hosted.md#the-receipt) from the project root
before and after the test, including after a failed command. `baseline` and
`receipt` give this run's twin traffic through the SDK; `veris sandbox trace
--service <twin> --since <watermark>` gives the same from the CLI with tiers
and bodies, and is what the ledger snapshots.

## Proxy and trust

What the SDK does at `create()`, so a reader can tell a missing piece from a
broken one:

| what | how |
|---|---|
| egress | `networkAllowList` = the Veris gateway's address as one `/32`, and `outboundProxyUrl` = the gateway. Daytona chains its own proxy (`HTTP_PROXY`, `HTTPS_PROXY`, lower-case twins and `NO_PROXY` are set in the box) to the gateway, which answers vendor hostnames from the twin and passes public hosts through. Never a `domainAllowList`. |
| trust | The Veris CA at `/tmp/veris-ca.crt`; a bundle of the public roots plus ours at `/tmp/veris-ca-bundle.crt`; eighteen path-valued variables (`SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `PIP_CERT`, …) pointing at it, returned by `getTrustEnv()`; a best-effort install into the system store and the JVM. Daytona overwrites four of those variables on its own commands, which is why every `exec` above re-applies the map. |
| Node | `NODE_USE_ENV_PROXY=1`, or Node ignores the proxy variables and Daytona blocks the direct dial. `NODE_OPTIONS=--use-openssl-ca`, or Node validates the gateway's leaf against Daytona's CA file and fails. `NODE_OPTIONS` also carries `--require /tmp/veris-node-proxy.cjs`: `NODE_USE_ENV_PROXY` reaches only Node's global agents and `fetch`, and an SDK that builds its own `https.Agent` for keep-alive (stripe-node, the AWS SDK, Twilio) otherwise resolves the vendor host itself and dies with `EAI_AGAIN`. Measured: global agent 200, own agent `EAI_AGAIN`, own agent with `proxyEnv` 200. |
| bundled CAs | An SDK that ships its own CA file reads no variable: stripe-python's first call fails with "Could not verify Stripe's SSL certificate". `patch-cas` appends the Veris CA to the known bundles (certifi, pip's vendored certifi, botocore, stripe, httplib2); run it after every dependency install. Anything else is [troubleshooting.md](troubleshooting.md)'s over-mount procedure, done inside the box with `exec`. |

Three rules follow from that table:

- `NODE_OPTIONS` is one variable. An application that sets its own value
  (`--experimental-vm-modules`, `--max-old-space-size`) replaces the SDK's
  flags and every Node vendor call fails on DNS or on the certificate. Build
  it with the SDK's `verisNodeOptions()`, which appends them once.
- Never set proxy or CA variables of your own, disable verification, or point
  the application at the twin's URL. The application keeps its production
  hostnames; the box's egress is what makes them reach the twin.
- A client built on undici `Pool` or `Client`, or any client that verifies a
  pinned certificate, is not covered by any of the above. Stop and report it.

## Data planes

A data-plane twin (postgres, yente) is handed over, not intercepted: its DSN
arrives in the box under the variable `veris services` names
(`DATABASE_URL`), and `getDataPlaneEnv()` returns the same map. Whether the
box can reach that address is a platform question, and as of 0.3.0 on
2026-09-08 the answer is no: with `outboundProxyUrl` set, Daytona's proxy is
the box's only way out and it tunnels CONNECT to port 443 only (measured:
`CONNECT <pg-gateway>:5432` times out, `:443` is accepted; a direct dial fails
even with the address on the allowlist). Postgres clients speak no HTTP proxy
either. The design that fixes it (a data plane served on 443 and a forwarder in
the box) is veris-ai/veris-daytona's open issue; until it ships, an
application that needs its own database runs it inside the box: for Postgres, `embedded-postgres` from npm
(`initdb` and `pg_ctl` from its `native/bin`, a port on `127.0.0.1`, the
`DB_*` or `DATABASE_URL` variables the application reads set on each `exec`).
Postgres refuses to run as root, so this needs the default snapshot's
`daytona` user or the package's `createPostgresUser` option on a root image.
Say in *What the twin cannot represent* that the database is the box's, not
the platform's.

## Callbacks

`sbx.veris.deliverTo(port)` points every twin's callbacks at the box's preview
URL for that port, and `deliverTo(null)` unregisters. The application must
listen on `0.0.0.0`. Check the twin's current destination first, record it,
and restore it before deleting the box; the destination belongs to the whole
twin. Prove delivery with `delivery` entries in the trace and the
application's own handling, as [webhooks.md](webhooks.md) says.

## Teardown and limitations

After saving evidence and restoring any callback registration, delete the
box (`sbx.delete()`), then `veris down` from the project root. Deleting needs
the key's delete permission; without it the box lives until its own brakes
(30 idle minutes, then 60 minutes, then 4 hours in all).

- The box and the twin have separate lifetimes; neither extends the other.
  A 120-minute twin fits a setup, a red, a fix and a green, but not with much
  to spare: snapshot every exchange the ledger cites as it happens.
- `receiptSince()` counts what the twin logged since the baseline, across
  everything that reached it; the CLI's trace with `--tier handler` is what
  separates the application's calls from control traffic.
- A `create()` that fails after Daytona accepted the request leaves a box in
  `build_failed`; the SDK reaps it and names the reason. A `create()`
  interrupted between the accept and the state file needs the box found in
  Daytona by its `veris_twin_id` label and deleted by hand.
- If a release prerequisite or missing credential prevents the run, report it
  and say **live execution was not tested**. A canary, a receipt count or a
  green shell exit alone does not prove the application reached the twin.
