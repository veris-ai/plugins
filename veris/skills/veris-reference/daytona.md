# Daytona: provider recipe for the hosted tier

Read [hosted.md](hosted.md) for tier selection, workload preparation, the trace
as receipt, project notes and cleanup ownership. This recipe uses the published
[@veris-ai/daytona SDK](https://www.npmjs.com/package/@veris-ai/daytona) from
[veris-daytona](https://github.com/veris-ai/veris-daytona), a drop-in for
`@daytona/sdk`, to manage a separate application-test box attached to the
task's existing twin. It is the same shape as the [E2B recipe](e2b.md): a
task-local script over the SDK, not a CLI. OpenCode provider configuration and
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

The recipe needs, at least, **0.3.0**: `veris.attachSandboxId` on `create()`,
the gateway address pin (`networkAllowList`, never a `domainAllowList`, which
turns on Daytona's TLS inspection and ends every vendor call in a 502),
`receiptBaseline()` / `receiptSince()`, `getTrustEnv()` and
`patchBundledCas()`. 0.2.1 and earlier have none of that; if `latest` is older
than 0.3.0, stop and report the release prerequisite. Do not clone or build
unreleased code to fill the gap. A Node application whose SDK builds its own
`https.Agent` (stripe-node, the AWS SDK, Twilio) additionally needs the Node
proxy preload described under *Proxy and trust*, shipped from 0.3.1; with
0.3.0 the runner script below installs the same preload itself.

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

Save the following as `.veris/daytona/sandbox.mjs` and run it from that
directory. It is a task-local script over the supported SDK; the verbs are
the ones `build` and `fix` expect.

```js
import { readFileSync, writeFileSync, unlinkSync, existsSync } from "node:fs"
import { execFileSync } from "node:child_process"
import path from "node:path"
import { Daytona } from "@veris-ai/daytona"

const [action, ...args] = process.argv.slice(2)
const HERE = path.dirname(new URL(import.meta.url).pathname)
const STATE = path.join(HERE, "sandbox.json")
const BASELINE = path.join(HERE, "baseline.json")
const twinId = process.env.VERIS_TWIN_ID
if (!twinId) throw new Error("Set VERIS_TWIN_ID to this task's existing twin")
const daytona = new Daytona({ apiKey: process.env.DAYTONA_API_KEY })
const state = () => JSON.parse(readFileSync(STATE, "utf8"))
const box = async () => {
  const s = state()
  if (s.twinId !== twinId) throw new Error("sandbox.json belongs to another twin")
  return daytona.get(s.daytonaSandboxId)
}
const flag = (name) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined)

// Merges the SDK's NODE_OPTIONS (the trust flag and, from 0.3.1, the proxy
// preload) into a caller's own, so `--env NODE_OPTIONS=…` never drops them.
const NODE_PRELOAD = "/tmp/veris-node-proxy.cjs"
const nodeOptions = (own = "") =>
  [own, `--require ${NODE_PRELOAD}`, "--use-openssl-ca"]
    .filter((flag, i) => flag && (i === 0 || !own.includes(flag)))
    .join(" ").trim()

switch (action) {
  case "create": {
    if (existsSync(STATE)) throw new Error("sandbox.json exists: delete that task box first")
    const image = flag("--image")
    const sbx = await daytona.create({ ...(image ? { image } : {}), veris: { attachSandboxId: twinId } })
    const home = (await sbx.process.executeCommand("echo $HOME")).result.trim()
    const workDir = `${home}/veris-run`
    await sbx.process.executeCommand(`mkdir -p ${workDir}`)
    // With an SDK older than 0.3.1 the proxy preload is not in the box; put it there.
    const preload = [
      'for (const mod of [require("http"), require("https")]) {',
      "  const Base = mod.Agent",
      "  mod.Agent = class Agent extends Base { constructor(o) { super({ proxyEnv: process.env, ...(o || {}) }) } }",
      "}", "",
    ].join("\n")
    await sbx.fs.uploadFile(Buffer.from(preload), NODE_PRELOAD)
    const info = {
      daytonaSandboxId: sbx.id, twinId: sbx.verisSandboxId, workDir,
      trustEnv: sbx.veris.getTrustEnv(),
      services: (await sbx.veris.services()).map((s) => s.name),
    }
    if (info.twinId !== twinId) { await sbx.delete(); throw new Error("attached to an unexpected twin") }
    writeFileSync(STATE, JSON.stringify(info, null, 2), { mode: 0o600 })
    console.log(JSON.stringify({ daytonaSandboxId: info.daytonaSandboxId, twinId: info.twinId, workDir, services: info.services }))
    break
  }
  case "push": {                      // push <staging dir>
    const dir = path.resolve(args[0])
    const s = state(); const sbx = await box()
    const tgz = path.join(HERE, "workload.tgz")
    execFileSync("tar", ["-czf", tgz, "-C", dir, "--exclude=.git", "--exclude=node_modules", "--exclude=dist",
      "--exclude=.venv", "--exclude=venv", "--exclude=__pycache__", "--exclude=._*", "."],
      { env: { ...process.env, COPYFILE_DISABLE: "1" } })
    await sbx.fs.uploadFile(tgz, `${s.workDir}.tgz`)
    const r = await sbx.process.executeCommand(`tar -xzf ${s.workDir}.tgz -C ${s.workDir} && du -sh ${s.workDir}`)
    process.stdout.write(r.result); process.exit(r.exitCode)
  }
  case "exec": {                      // exec [--cwd d] [--env K=V]... [--timeout s] -- <command>
    const s = state(); const sbx = await box()
    const sep = args.indexOf("--")
    const opts = args.slice(0, sep); const command = args.slice(sep + 1).join(" ")
    const env = { ...s.trustEnv }; let cwd = s.workDir; let timeout = 1800
    for (let i = 0; i < opts.length; i++) {
      if (opts[i] === "--cwd") cwd = path.isAbsolute(opts[++i]) ? opts[i] : `${s.workDir}/${opts[i]}`
      else if (opts[i] === "--env") { const [k, ...v] = opts[++i].split("="); env[k] = k === "NODE_OPTIONS" ? nodeOptions(v.join("=")) : v.join("=") }
      else if (opts[i] === "--timeout") timeout = Number(opts[++i])
    }
    const r = await sbx.process.executeCommand(command, cwd, env, timeout)
    process.stdout.write(r.result.endsWith("\n") ? r.result : r.result + "\n"); process.exit(r.exitCode)
  }
  case "patch-cas": { console.log(JSON.stringify(await (await box()).veris.patchBundledCas())); break }
  case "baseline": {                  // before every run
    const b = await (await box()).veris.receiptBaseline()
    writeFileSync(BASELINE, JSON.stringify(b, null, 2)); console.log(JSON.stringify(b)); break
  }
  case "receipt": {                   // what the twin received since the baseline
    const r = await (await box()).veris.receiptSince(JSON.parse(readFileSync(BASELINE, "utf8")))
    console.log(JSON.stringify(r, null, 2)); break
  }
  case "delete": {                    // the box; the attached twin is left running
    const sbx = await box(); await sbx.delete(); unlinkSync(STATE)
    console.log(`deleted Daytona sandbox ${sbx.id}; twin ${sbx.verisSandboxId} left running`); break
  }
  default: console.error("create | push <dir> | exec [opts] -- <cmd> | patch-cas | baseline | receipt | delete"); process.exit(2)
}
```

For an npm application with a lockfile, the run lines are:

```sh
node sandbox.mjs create                        # or: create --image node:20-bookworm
node sandbox.mjs push /path/to/staging
node sandbox.mjs exec -- 'node --version && npm ci'
node sandbox.mjs patch-cas                      # after dependencies are in; see Proxy and trust
node sandbox.mjs baseline
# On the controlling machine, in the project root, capture each twin's watermark.
node sandbox.mjs exec --timeout 900 --env KEY=value -- 'npm test'
node sandbox.mjs receipt
```

Replace the install and test commands with this project's actual commands
and record them in *How to run*, with the exact `--env` values the app needs
(credentials come from the twin's manual and `veris sandbox data get`, never
from the real vendor). Each `exec` runs one shell string from `workDir` with
the trust variables applied, returns the command's own exit code, and returns
output when the command ends rather than streaming it; a long install shows
nothing until it finishes. `--env NODE_OPTIONS=…` keeps the SDK's flags
merged in. After editing source locally, `push` again; files removed locally
stay in the box, so delete them there or create a fresh box before measuring
a change that removes files.

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
| Node | `NODE_USE_ENV_PROXY=1`, or Node ignores the proxy variables and Daytona blocks the direct dial. `NODE_OPTIONS=--use-openssl-ca`, or Node validates the gateway's leaf against Daytona's CA file and fails. From 0.3.1, `NODE_OPTIONS` also carries `--require /tmp/veris-node-proxy.cjs`: `NODE_USE_ENV_PROXY` reaches only Node's global agents and `fetch`, and an SDK that builds its own `https.Agent` for keep-alive (stripe-node, the AWS SDK, Twilio) otherwise resolves the vendor host itself and dies with `EAI_AGAIN`. Measured: global agent 200, own agent `EAI_AGAIN`, own agent with `proxyEnv` 200. The script above installs the same preload when the SDK is older. |
| bundled CAs | An SDK that ships its own CA file reads no variable: stripe-python's first call fails with "Could not verify Stripe's SSL certificate". `patch-cas` appends the Veris CA to the known bundles (certifi, pip's vendored certifi, botocore, stripe, httplib2); run it after every dependency install. Anything else is [troubleshooting.md](troubleshooting.md)'s over-mount procedure, done inside the box with `exec`. |

Three rules follow from that table:

- `NODE_OPTIONS` is one variable. An application that sets its own value
  (`--experimental-vm-modules`, `--max-old-space-size`) replaces the SDK's
  flags and every Node vendor call fails on DNS or on the certificate. Pass it
  through `exec --env NODE_OPTIONS=…`, which merges, or build it with the
  SDK's `verisNodeOptions()`.
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

After saving evidence and restoring any callback registration, `node
sandbox.mjs delete`, then `veris down` from the project root. Deleting needs
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
