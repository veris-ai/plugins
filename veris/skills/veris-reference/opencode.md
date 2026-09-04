# OpenCode provider sessions

Use with [session.md](session.md), not the hosted CLI runner recipes. The reasoning
loop and plugin callbacks run on the host; the provider's bash/read/write/edit/
multiedit/ls/glob/grep tools operate on remote application files. `verisSkill`
reads this installed package on the host, independent of those replacements. Use
it for all linked references and required scripts, with package-relative paths.

## Install and record the resolution

These are OpenCode plugins, not `npx` commands. In `opencode.json` (or the global
OpenCode config), select **one** provider. The renamed skills package in this
example needs its first npm release:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@veris-ai/veris-opencode@latest",
    "@veris-ai/daytona-opencode@latest"
  ]
}
```

For E2B replace only the second entry with `@veris-ai/e2b-opencode@latest`.
Never install both sandbox plugins in one session: they replace the same tools.
Restart OpenCode after changing config. The commands are `/veris:setup`,
`/veris:build <request>` and `/veris:fix <request>`.

Resolve published versions on the **host**, using `npm view <package>@latest
version` and the installed/cache manifests and lockfile. Record the actual skills,
provider plugin, transitive provider SDK and OpenCode versions in setup notes;
a registry lookup alone does not prove what a cached session loaded. Pin those
resolved npm versions in config for replay. `verisSkill` returns its own installed
version and the current OpenCode session id. Never replace an unavailable release
with a Git SHA checkout/build recipe.

Release inspection on 2026-09-04: the old skills package
**@veris-ai/veris-sim-opencode 0.7.0**, Daytona plugin/SDK **0.2.1**, E2B plugin/SDK
**0.1.1**; OpenCode plugin API **1.18.28**, locally installed OpenCode **1.18.25**.
The old skills tarball uses `/veris-sim:*` commands and host-file templates.
The next release is **@veris-ai/veris-opencode 0.7.3**, aligning the name with
`veris` in Claude and Codex and adding `verisSkill`. That new npm name is not yet
published; its first release and trusted-publisher setup remain prerequisites.
After release, replace the old package entry in all applicable OpenCode configs
with the new one and restart; do not load both skills packages. Commands use
`/veris:*`. The former source name `opencode-veris` was unpublished too.

The package is built from canonical `veris/skills` by `veris/.opencode-plugin`;
the old `veris-sim/` source directory is not an installation path. Package renaming
does not require changes to the selected provider plugin or its session ownership.

## Discovery and control access

| Concern | Daytona | E2B |
|---|---|---|
| Host credentials | `DAYTONA_API_KEY`, `VERIS_API_KEY`, `VERIS_ENVIRONMENT_ID` | `E2B_API_KEY`, `VERIS_API_KEY`, `VERIS_ENVIRONMENT_ID` |
| Optional host settings | `DAYTONA_SNAPSHOT`, `VERIS_API_BASE`; SDK honors Daytona API settings | `VERIS_E2B_TEMPLATE`, `VERIS_API_BASE` |
| Current identity | `verisTwin` without arguments lists twin id and services; compare with unfiltered `verisReceipt` | Unfiltered `verisReceipt` supplies the twin id and HTTP service names, even when traffic is zero; no `verisTwin` tool |
| Repository | Provider context identifies it; verify remotely (published default `/home/daytona/project`) | Provider context identifies it; verify remotely (published default `/home/user/project`) |
| Manual | `verisTwin` with `service` | No manual plugin tool; discover a reachable service control route or host interface |
| MCP | Registers host `veris` at the configured API base's `/mcp` when `VERIS_API_KEY` exists | Does not register MCP |

Both plugin entrypoints require the named host environment variables; the CLI's
login profile alone does not meet those plugin checks. Do not copy provider/control
keys into the sandbox or print them. Application credentials come from the service
manual/seed, not a provider API key. E2B's full receipt lists HTTP services only;
use service metadata to discover any data planes the application needs.

Inspect the actual available MCP tools and their schemas. Daytona fills missing
permissions with create/delete denied and reset/promote asking; existing user
values win, including a scalar global permission. Leave these settings intact.
The skills adapter registers no MCP and alters no permissions or provider tools.
For E2B, if service metadata/host lifecycle inspection is needed, the host can add
this explicit configuration (the API base must match the provider):

```json
{
  "mcp": {
    "veris": {
      "type": "remote",
      "url": "https://svc.api.veris.ai/mcp",
      "headers": { "X-API-Key": "{env:VERIS_API_KEY}" },
      "oauth": false
    }
  },
  "permission": {
    "veris_create_sandbox": "deny",
    "veris_delete_sandbox": "deny",
    "veris_reset_sandbox": "ask",
    "veris_promote_sandbox": "ask"
  }
}
```

Merge with existing host settings without replacing user choices. MCP is not
assumed to expose service data mutations: the inspected server exposes environment,
sandbox and clock/lifecycle operations. Use `get_sandbox` with the live twin id to
obtain service coordinates when its schema supports that lookup. Do not infer
MCP tool names for seeding, schema or faults.

For service operations, use the returned service `control_url` through an available
host HTTP tool, or test the intercepted vendor hostname's `/veris/manual` and
`/veris/schema` with a **read-only** remote request. Only use the latter after the
provider identifies that service and the response is the expected Veris control
shape. Closed PR #30 measured this route in one Daytona session; it is not a
universal gateway guarantee. A direct control URL can be blocked remotely even
when the vendor route works. Never widen egress to reach it.

After verifying a service control route, the shared HTTP control contract provides:

| Operation | Interface (relative to that service's control base) |
|---|---|
| Manual, schema, operation coverage | `GET /veris/manual`, `/veris/schema`, `/veris/operations` |
| Counts and rows | `GET /veris/data`; select a table with `entity_type`, page with `limit`/`offset` and match returned ids |
| Add seed/fault rows | `POST /veris/data` with `{"data":{"<table>":[<rows>]}}`; use the schema's row shape and manual's fault contract |
| Update/re-arm an existing row | `PATCH /veris/data` with the same data envelope and the actual row id; read back the result |
| Current-run trace and bodies | `GET /veris/requests?since_id=<id>&tier=handler&order=asc&limit=<n>`; also read `tier=fault`; retain full entries and paginate by advancing the service watermark until complete |
| File bytes | `/veris/files`, following [state.md](state.md)'s upload/read-back contract |

Confirm the installed service supports the required operation; a schema does not
establish vendor behavior. The request-log default is a bounded page (50 in the
inspected control implementation), explaining why the SDK's count can plateau.
An empty page only ends pagination after a successful read on the same service;
check for resets and gaps. Bodies may be redacted or unavailable: keep the gate's
response/state assertion, and report exactly what cannot be observed.

Use [twin.md](twin.md), [state.md](state.md) and [faults.md](faults.md) for the
measurement/seed rules. Service control payloads are keyed by table, while CLI
seed files are keyed by service: do not send a CLI envelope to `/veris/data`.
Treat all these operations as probes/control work, outside application receipt
windows. If neither the host interface nor the intercepted control route supports
the operation, name exactly what is missing (for example E2B manual access, fault
writes, trace bodies or file upload) and leave the dependent gate unproven. Do not
substitute a mock or a new twin.

## Trust, network, lifetime and synchronization

| Concern | Daytona | E2B |
|---|---|---|
| Network | Published SDK uses a gateway outbound proxy plus a domain allowlist of vendor/gateway/data-plane/registry hosts by default; blocked destinations remain blocked | Plugin explicitly requests `egress: 'open'`; SDK uses gateway interception with open egress. Do not claim unknown vendors are blocked or exclusive twin access |
| Receipt blind spots | Reports mode, integrity and leaks; retain those claims verbatim | Open egress reports `udp-quic-possible` and `ech-possible`; gateway canary verifies that route, not all application egress |
| TLS | SDK installs the gateway CA and supplies trust variables. Published 0.2.1 differs from newer source's combined-store and `NODE_OPTIONS=--use-openssl-ca` handling | SDK installs the CA, supplies system-bundle trust variables and `NODE_EXTRA_CA_CERTS`; command wrapper reapplies trust defaults |
| Initial source | Host pushes committed `HEAD` over Daytona SSH; uncommitted host edits do not arrive | Committed `HEAD` travels via git bundle and E2B filesystem APIs; no SSH |
| Return changes | `gitSync` commits remotely and pulls to local `opencode/N`; SSH host-key/network errors can prevent sync | `gitSync` commits remotely and transports a bundle to local `opencode/N`; idle sync is best effort |
| Persistence | Host storage maps sessions to sandboxes; reconnect retrieves/starts them. Platform idle/stop/delete settings apply; the plugin does not set a guaranteed TTL | Mapping persists across restarts. Plugin uses 20-minute timeout, refreshes on tool use at most every 5 minutes, and requests pause/auto-resume |
| Cleanup | Session deletion invokes sandbox deletion and deletion of its owned twin; quitting OpenCode does not request that cleanup | Session deletion calls `kill`, deleting the owned twin; quitting does not. Paused files can survive, but an expired twin can still invalidate evidence |

Preserve the installed provider's trust configuration, including any existing
`NODE_OPTIONS`. Do not impose newer source's values on an older release. Test HTTPS
with defaults; a failure is a precise provider release/certificate prerequisite,
not permission to turn verification off. Daytona's current source contains trust
fixes absent from the inspected 0.2.1 release, so a runtime needing those fixes is
blocked until a published SDK/plugin combination supplies them. Report actual
resolved versions and symptoms instead of promising all runtimes work on 0.2.1.

Daytona SSH trust must be provisioned on the host (supported versions honor
`DAYTONA_SSH_KNOWN_HOSTS`); preserve verification. E2B bundles avoid that dependency.
Neither plugin imports later local edits automatically; commit and start a new
session to send a new base. Both own the local `opencode/N` destination and can
overwrite edits made there. Ignored evidence is absent from these git transports;
follow [session handoff](session.md#hand-back-code-and-evidence) explicitly.
A sandbox's filesystem surviving is not proof that its twin or history survived.

Sources checked: published tarballs and current source for
[Daytona](https://github.com/veris-ai/veris-daytona/tree/main/daytona-opencode),
[E2B](https://github.com/veris-ai/veris-e2b/tree/main/e2b-opencode), and their SDKs;
OpenCode's [plugins](https://opencode.ai/docs/plugins/),
[custom tools](https://opencode.ai/docs/custom-tools/) and
[MCP configuration](https://opencode.ai/docs/mcp-servers/).
