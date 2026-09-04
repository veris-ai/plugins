# E2B: provider recipe for the hosted tier

Read [hosted.md](hosted.md) for selection, workload preparation, trace evidence,
project notes and cleanup ownership. This recipe uses the published
[@veris-ai/e2b SDK](https://www.npmjs.com/package/@veris-ai/e2b) from
[veris-e2b](https://github.com/veris-ai/veris-e2b) to manage a separate application-test
box attached to the task's existing twin. OpenCode provider configuration and
session-owned sandboxes belong to a separate workflow.

## Prerequisites and the release

The controlling machine needs Node 20 or newer, npm, tar and a working `veris`
installation. First check the credentials, gateway and template requirements below,
before creating resources.

Reuse the exact SDK version in `.veris/NOTES.md`. On first setup, resolve latest
once and record the concrete result, then use that version for the entire task:

```sh
npm view @veris-ai/e2b@latest version
# Put the returned concrete version in <version> for all following commands.
npm view @veris-ai/e2b@<version> version bin engines dependencies exports --json
npm pack @veris-ai/e2b@<version> --dry-run --json
```

As checked on 2026-09-04, latest is **0.1.1**. Its 20-file npm tarball exports ESM,
CommonJS and TypeScript declarations, with **no `bin` entry or CLI file**. Use the
SDK below; there is no `npx veris-e2b` or Daytona-style runner. The tarball also
omits the repository's `examples/` and `docs/`; those paths in its README are not
installed programs. This recipe was checked against 0.1.1 with its published `e2b`
dependency resolved to **2.46.1**.

Create a local runner directory, excluded from git and from the workload upload:

```sh
mkdir -p .veris/e2b
cd .veris/e2b
npm init -y
npm install --save-exact --ignore-scripts @veris-ai/e2b@<version>
npm ls @veris-ai/e2b e2b
node --input-type=module -e 'import { Sandbox, SDK_VERSION } from "@veris-ai/e2b"; console.log(SDK_VERSION, typeof Sandbox.create, typeof Sandbox.connect, typeof Sandbox.kill)'
```

Keep this runner's `package.json` and `package-lock.json` for the task; use
`npm ci --ignore-scripts` when restoring it. The Veris package permits newer E2B 2.x releases,
so the lockfile also fixes the underlying SDK. Record both resolved versions in
*How to run*. Verify any different release against its shipped declarations and
implementation. Missing attachment, egress proxy, trust, file or command support is
a release prerequisite: report it before `veris up`. Do not clone or build
unreleased integration code to fill a gap.

### Credentials and gateway

- `E2B_API_KEY`, from the [E2B dashboard](https://e2b.dev/dashboard), must be authorized
  to create, access and kill sandboxes in the selected team and use its template.
- `VERIS_API_KEY` must access the same plane and twin as the controlling `veris` CLI.
  The SDK reads this variable or `veris.apiKey`; 0.1.1 does **not** load `veris login`
  profiles or `VERIS_PROFILE`. A signed-in CLI alone is insufficient. Obtain the key
  through the engineer's authorized credential source; never print it or copy either
  control key into the workload.
- Set `VERIS_API_BASE` to the trusted plane shown by `veris whoami` (the SDK default
  is `https://svc.api.veris.ai`). Run the CLI with that same credential and plane.
- The plane must offer a reachable gateway and an egress credential compatible with
  this SDK. E2B must support `network.egressProxy` (E2B Cloud or a supporting BYOC
  deployment; the open-source self-hosted infrastructure does not). Check
  `veris doctor` as described in [hosted.md](hosted.md#choosing-it).

The recipe forces `mode: 'gateway'`: 0.1.1 cannot honor `attachSandboxId` in proxy
mode. If the plane declines this release, the gateway is unavailable, or the canary
fails, stop and report that prerequisite. Removing attachment or switching to proxy
would change which twin and lifecycle the task uses.

### Template and runtime

Choose an existing E2B template name or ID accessible to the key, passed as the first
argument to `Sandbox.create(template, options)`. Record its ID/build and actual
runtime versions. Omitting it selects E2B's `base` template; check its contents
instead of assuming a particular Node or Python version. A Docker tag or Daytona
snapshot is not an E2B template.

The template must contain the application's runtime, a POSIX shell, `tar`, `curl`,
and `ca-certificates` / `update-ca-certificates`, with root available for the SDK's
CA installation. Provision a suitable E2B template separately if one is missing.
Dependencies can be preinstalled there or installed below. Runtime downloads,
native build tools and postinstall binary downloads need their own hosts allowed;
a prebuilt template avoids that preparation during each test run.

## Attach, upload and run

From the project root, run `veris up` or reuse its already-running task twin.
`veris status` and `.veris/twin.local.yaml`'s `sandbox.id` identify it. Export
`VERIS_TWIN_ID=<that-id>` in the controlling shell. This is the existing twin's ID,
not the E2B box ID. Leave `VERIS_ENVIRONMENT_ID` unset for this recipe: attachment
derives the environment from the twin, and a stale override can misdirect later
updates. Creation with attachment leaves the twin's TTL unchanged.

Prepare a reviewed staging directory containing the current application source,
lockfiles, tests and only the twin credential files it needs. Include uncommitted
changes deliberately. Exclude `.git`, the local E2B runner, dependencies to rebuild,
control-plane keys and unrelated secrets. The archive uploads **everything** in
this directory; neither the SDK nor tar applies `.gitignore` or Daytona exclusions.
With `VERIS_E2B_UPLOAD_DIR` set to that absolute directory, run from `.veris/e2b`:

```sh
tar -czf workload.tgz -C "$VERIS_E2B_UPLOAD_DIR" .
tar -tzf workload.tgz
```

Save the following as `.veris/e2b/sandbox.mjs`. This is a task-local script using
the supported SDK, not a CLI published by the package. Run it from that directory.
Set `E2B_TEMPLATE` to the chosen template and adjust the initial `allowOut` list
for the application's install (shown here for an npm project).

```js
import { readFile, writeFile, unlink, access } from 'node:fs/promises';
import { Sandbox, CommandExitError } from '@veris-ai/e2b';

const [action, command] = process.argv.slice(2);
if (!['create', 'run', 'receipt', 'kill'].includes(action)) {
  throw new Error('Use create, run <shell-command>, receipt, or kill');
}
const twinId = process.env.VERIS_TWIN_ID;
if (!twinId) throw new Error('Set VERIS_TWIN_ID to this task\'s existing twin');
const stateFile = new URL('./sandbox.json', import.meta.url);

if (action === 'create') {
  try {
    await access(stateFile);
    throw new Error('sandbox.json exists: finish and kill that task box first');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  if (!process.env.E2B_TEMPLATE) throw new Error('Set E2B_TEMPLATE');
  if (process.env.VERIS_ENVIRONMENT_ID) throw new Error('Unset VERIS_ENVIRONMENT_ID for attachment');
  const bytes = await readFile(new URL('./workload.tgz', import.meta.url));
  const sbx = await Sandbox.create(process.env.E2B_TEMPLATE, {
    timeoutMs: 30 * 60_000,
    network: { allowPublicTraffic: false },
    veris: {
      attachSandboxId: twinId,
      mode: 'gateway',
      egress: 'strict',
      allowOut: ['registry.npmjs.org'],
      installCa: true,
      dataPlaneEnv: true,
    },
  });
  try {
    // Save the E2B ID immediately so cleanup remains possible after interruption.
    await writeFile(stateFile, JSON.stringify({ e2bId: sbx.sandboxId, twinId }), { mode: 0o600 });
    console.log(JSON.stringify({ e2bId: sbx.sandboxId, twinId: sbx.verisSandboxId }));
    if (sbx.verisSandboxId !== twinId || sbx.verisMode !== 'gateway') {
      throw new Error('Unexpected twin or interception mode');
    }
    await sbx.files.write('/tmp/workload.tgz',
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    await sbx.commands.run('mkdir -p /home/user/app && tar -xzf /tmp/workload.tgz -C /home/user/app');
  } catch (error) {
    await sbx.kill(); // Attached twin survives; keep state for cleanup verification.
    throw error;
  }
} else {
  const state = JSON.parse(await readFile(stateFile, 'utf8'));
  if (state.twinId !== twinId) throw new Error('State belongs to another twin');
  if (action === 'kill') {
    // Inherited E2B static method: needs only the E2B key, even if the twin expired.
    await Sandbox.kill(state.e2bId);
    await unlink(stateFile);
  } else {
    if (action === 'run' && !command) throw new Error('Pass one quoted shell command');
    const sbx = await Sandbox.connect(state.e2bId);
    if (sbx.verisSandboxId !== twinId || sbx.verisMode !== 'gateway') {
      throw new Error('Unexpected twin or interception mode');
    }
    if (action === 'receipt') {
      const receipt = await sbx.veris.receipt();
      await writeFile(new URL('./receipt.json', import.meta.url),
        JSON.stringify(receipt, null, 2), { mode: 0o600 });
      console.log(receipt.mode, receipt.integrity, receipt.leaks);
    } else {
      try {
        await sbx.commands.run(command, {
          cwd: '/home/user/app',
          timeoutMs: 10 * 60_000,
          envs: { ...await sbx.veris.getDataPlaneEnv(), ...await sbx.veris.getTrustEnv() },
          onStdout: (text) => { process.stdout.write(text); },
          onStderr: (text) => { process.stderr.write(text); },
        });
      } catch (error) {
        if (!(error instanceof CommandExitError)) throw error;
        process.exitCode = error.exitCode;
      }
    }
  }
}
```

`files.write` accepts bytes as an `ArrayBuffer`; there is no recursive `push` API.
This archive preserves executable bits and symlinks, so review their targets too.
The example assumes a template with a writable `/home/user`; adjust the work
directory for another template. Rebuild the archive after local edits. For a
rerun with changed files, kill the task box and create it again from that archive,
so removed files do not remain remotely. The twin stays available across these runs.

For an npm application with a lockfile, the run lines are:

```sh
node sandbox.mjs create
node sandbox.mjs run 'node --version && npm --version'
node sandbox.mjs run 'npm ci'
# Finish any client-specific certificate preparation described below.
# On the controlling machine, in the project root, capture each twin's watermark.
# Then run the application's actual test flow:
node sandbox.mjs run 'npm test'
node sandbox.mjs receipt
```

Replace the install and test commands with this project's actual commands and
record them in *How to run*. Each `run` takes one shell string, sets `cwd`, passes
the trust and data-plane variables, streams output and preserves a nonzero command
exit code. Variables in single-quoted commands expand remotely, e.g.
`node sandbox.mjs run 'export KEYS_DIR="$PWD/test-keys"; npm test'`. Use the variable
the app already reads and the credentials the twin publishes. Shell exports from
one invocation do not persist into the next.

Read [the shared receipt rule](hosted.md#the-receipt) from the project root before
and after the test, including after a failed command. Save application `handler`
or `fault` entries since each watermark and the tested state/response. The SDK's
`receipt()` and `assertTouched()` read a cumulative request list without a `since`
filter or trace-tier filter; they cannot attribute a call to this run on a reused
twin. `integrity: 'verified'` describes its canary check, not an application test.

## Certificate trust

Gateway creation writes `/usr/local/share/ca-certificates/veris-ca.crt`, rebuilds
`/etc/ssl/certs/ca-certificates.crt` as root, and injects a trust environment family.
Node gets the additive `NODE_EXTRA_CA_CERTS`; Requests, curl, npm, pip and other
supported clients use the system bundle including public roots. The SDK also
attempts JVM/NSS imports if their tooling already exists. In 0.1.1 the managed
trust and data-plane variables win over conflicting create-time `envs`; command
options can still override them. Do not replace them with local-machine paths.

The gateway CA is installed **before** dependency downloads. After installing
dependencies or a new runtime, check whether a client pins a private CA bundle or
scrubs its environment. Point a configurable client at the system bundle using
its supported trust option; if it ignores that, append the Veris CA to the actual
installed bundle using [troubleshooting.md](troubleshooting.md)'s certificate
procedure inside this box. Reapply JVM/browser trust if those runtimes were added
after creation. This release supplies no Daytona `patchBundledCasCommand` or
`/tmp/veris-patch-bundled-cas.sh`; do not disable TLS verification.

## Networking and callbacks

| Concern | Published E2B behavior and what to verify |
|---|---|
| Outbound policy | `veris.egress: 'strict'` builds deny-all plus vendor route hosts, the canary, `veris.allowOut` and non-HTTP data-plane hosts. Allowed TCP is tunneled through E2B's host-side SOCKS5 egress proxy. This is not Daytona's 20-domain list or its default registry allowances. The Veris E2B SDK does not implement that cap/trimming; the deployment still enforces its own limits. |
| Package downloads | No registries are allowed by default. npm commonly needs `registry.npmjs.org`; pip commonly needs `pypi.org` and `files.pythonhosted.org`. Inspect lockfiles, redirects and install scripts for additional GitHub/CDN/runtime hosts. Include them at creation and verify the real install; an allowance alone does not prove the target gateway forwards a host correctly. The Daytona GitHub finding concerns a shared gateway, so do not assume E2B fixes it. Upload or preinstall when the target plane cannot serve a download. |
| Policy changes | `sbx.veris.updateNetwork({ allowOut: [...] })` reasserts the gateway settings. Raw `sbx.updateNetwork()` can clear interception. In 0.1.1 additions made by the wrapper are not persisted to metadata for `connect()`, which rebuilds the original policy; this script reconnects per command, so change the create-time list and recreate the box. |
| Open egress | `veris.egress: 'open'` adds a catch-all; the SDK reports `udp-quic-possible` and `ech-possible` leaks. TCP still uses the gateway, so this is neither a general connectivity fix nor a strict test. Keep strict for this recipe; avoid broad CIDR allowances that bypass hostname interception. |
| Data planes | For non-HTTP service URLs, 0.1.1 derives allowed hosts and injects safe `{ env_hint: dsn }` entries, e.g. `DATABASE_URL`; `getDataPlaneEnv()` returns them. This permits wire-protocol connections, not vendor HTTP base-URL substitution. Verify a real application query and stored outcome; fetching the variables proves no connection. Missing/private/unreachable DSNs are prerequisites to resolve, and local databases do not move with the archive. |
| Callbacks | Supported through `sbx.veris.deliverTo(portOrUrl)`, independently of outbound policy. Create with **`network: { allowPublicTraffic: true }`** when needed. The underlying E2B 2.46.1 API does not accept the top-level `allowPublicTraffic` shown in the integration README. |

For callbacks, first check the attached twin's current callback destination and
record it: registration changes the whole twin, across services. Do not run competing
receivers against it. With public access selected at creation, adapt the following
SDK fragment in a script alongside `sandbox.mjs`, using this task's saved E2B ID:

```js
import { readFile } from 'node:fs/promises';
import { Sandbox } from '@veris-ai/e2b';
const { e2bId, twinId } = JSON.parse(await readFile(new URL('./sandbox.json', import.meta.url), 'utf8'));
if (twinId !== process.env.VERIS_TWIN_ID) throw new Error('Wrong task twin');
const sbx = await Sandbox.connect(e2bId);
// app.js must bind 0.0.0.0:3000; replace it with the real application's receiver.
await sbx.commands.run('node app.js', {
  cwd: '/home/user/app', background: true, timeoutMs: 20 * 60_000,
  envs: { ...await sbx.veris.getDataPlaneEnv(), ...await sbx.veris.getTrustEnv() },
});
// Replace /health with the application's readiness endpoint.
await sbx.commands.run('for i in $(seq 1 30); do curl -fsS http://127.0.0.1:3000/health >/dev/null && exit 0; sleep 1; done; exit 1');
const publicUrl = await sbx.veris.deliverTo(3000);
console.log(publicUrl); // https://${sbx.getHost(3000)}; give it to the app's registration flow.
```

Use the returned URL through the application's normal callback registration; the
SDK does not inject `VERIS_PUBLIC_URL`. `deliverTo` updates the destination before
probing and only requires **one** service to answer its reachability probe in
0.1.1. It neither rolls back a failed probe nor proves every required vendor delivered
a callback. Verify required-service `delivery` traces, the app's handling/signature
checks and its resulting state as in [webhooks.md](webhooks.md). Restore the previous
URL with `await sbx.veris.deliverTo(previousUrl)` or unregister a task-owned setting
with `await sbx.veris.deliverTo(null)` before deleting the receiver, including after
a probe failure. There is no `veris run --require-callback` verdict here.

## Teardown and limitations

After saving evidence and restoring any callback registration, run
`node sandbox.mjs kill`. The inherited static `Sandbox.kill(e2bId)` deletes only
the recorded E2B box, without reconnecting to an expired twin. With a live attached
instance, `await sbx.kill()` likewise preserves the twin. Then apply
[shared cleanup](hosted.md#cleanup) and run `veris down` from the project root when
the task is done. Never pass a session-owned E2B ID to this script.

- Sandbox timeout and command timeout are independent, in milliseconds. The example
  requests a 30-minute box; normal E2B creation kills it at timeout. Plan limits
  apply. Do not opt into pause/auto-resume for this task lifecycle. Explicitly kill
  on completion, failure or cancellation; after an interrupted create without a
  saved ID, find the task's box in E2B using its Veris metadata before deleting it.
- Attaching does not extend the twin TTL. The Veris instance `setTimeout()` attempts
  to extend the twin too, even when attached, and suppresses some extension errors
  in 0.1.1. Manage the twin lifetime on the controlling machine and check its actual
  expiry; do not infer it from the E2B timeout or `connect()`.
- If the plane stops offering egress credentials during a task, 0.1.1 `connect()`
  can return without a new canary check, while `receipt()` still labels gateway
  integrity as verified. That label alone is insufficient. Restored gateway support
  and a fresh successful create are prerequisites to resume after such a failure;
  always require the application trace evidence described above.
- Gateway HTTP/2 and WebSockets to mocked hosts are documented as unsupported;
  HTTP/1.1 over TLS is supported. Strict hostname filtering is intended to block
  QUIC/ECH bypasses; open egress and CIDR passthrough weaken that guarantee.
- `fork()` is refused by this SDK. An expired twin cannot be replaced under an
  existing box with `connect()`; create a new task twin and box instead.
- If a release prerequisite or missing credentials prevents the run, report it and
  say **live execution was not tested**. Package inspection, a canary, an SDK
  receipt count or a green shell exit alone does not prove an application reached
  the task's twin.
