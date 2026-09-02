# Platforms, as measured

Nothing here closes a gate. The session's own readings do — `setup` section 0
writes them to `.veris/session.md`, and `build` and `fix` read that file, never
this one. This is the one file under `skills/` that names a platform. Every row
is dated and pinned to the package it was read from, and goes stale the day that
package changes; the transcripts behind it are not in this repository. A
platform absent from this file is not a reason to guess: run section 0.

## Pins

| tree | version | read on |
|---|---|---|
| `@veris-ai/daytona` (SDK) | `0.2.0-rc.1` | 2026-08-31 |
| `@veris-ai/daytona-opencode` (plugin) | `0.2.0-rc.1` | 2026-08-31 |
| `veris-daytona` `main` | `fc07f90`, 0.2.1 | 2026-09-01 |
| `veris-e2b` (SDK `@veris-ai/e2b`) | `2.0.0-alpha.1` at `02e8421` (2026-08-26) | 2026-08-31 |
| `@veris-ai/e2b-opencode` (plugin) | `0.1.0` | 2026-08-31 |

## Readings, 2026-08-31, from inside the sandbox, one service (`stripe`)

| | Daytona | E2B as its plugin creates it (`egress: 'open'`) | E2B `strict` (the SDK default; the plugin does not use it) |
|---|---|---|---|
| vendor call via the twin | `401`, receipt saw 1 | `401`, receipt saw 1 | `401`, receipt saw 1 |
| `/veris/schema`, `/veris/data`, `POST /veris/data`, `/veris/requests` | `403` from the egress boundary | `200` | blocked |
| `example.com` | `403` from the boundary; body not kept, so no signature yet (P6) | `200`, the real internet | blocked; `curl: (52) Empty reply from server` |
| `registry.npmjs.org`, `raw.githubusercontent.com` | `200` (allowlisted) | `200` | both blocked |
| receipt header | `interception: gateway   integrity: verified` | same, 2 blind spots named | same, 0 |

As `session.md` lines: Daytona `control_url` unanswered (below), `egress:
boundary-refused`, `staging: npm` or `raw`; E2B open `control_url` answers,
`egress: open`, `staging: npm` or `raw`; E2B strict `control_url` unanswered,
`egress: boundary-refused`, `staging: unreachable` — a session that cannot
finish setup by any route.

## The control-plane allowlist entry

Veris states the twin's control-plane hosts are on every sandbox's allowlist.
As of `veris-daytona` `main` at `fc07f90` (0.2.1, 2026-09-01) the code does not
show it: `buildNetwork` (`src/network.ts:171`) composes `domainAllowList` from
`vendorHosts`, `gatewayHosts`, `dataPlaneHosts`, `DEFAULT_REGISTRY_HOSTS` and the
caller's `allowOut`, and `src/state.ts:4` still says `control_url` is left off
on purpose. Until a release carries the entry, every `/veris/*` call from inside
a Daytona sandbox answers `403` at the boundary and section 0 stops. The first
version on which `GET $CONTROL_URL/veris/schema` answered `200` from inside is
P5's row, not yet written. Neither plugin tool prints `control_url` (the SDK
holds it as `ReceiptEntry.controlUrl` and does not render it); `get_sandbox` is
the route section 0 uses, and P5 confirms it works from inside.

## What `egress: open` costs

A host the twin does not answer for is not blocked: a vendor the environment
never modelled is called for real, with real credentials, and a green result
proves nothing. Only the twin's service list and the receipt decide whether a
call was intercepted. The same sandbox reaches `/veris/reset`, so the receipt
is read after the run and never cleared before it (`state.md`). E2B's `strict`
closes both, and also removes both staging routes — its SDK's network builder
has no registry allowlist — so on that platform package installs and receipt
integrity are a trade, not a setting.

## Asymmetries

- **Twin tool.** Daytona's plugin ships `verisTwin` (twin id, service list, a
  service's manual). E2B's ships no twin tool and no `manual()`; there the twin
  id comes only from the receipt header, and the manual by `curl` at
  `control_url`.
- **Receipt tool.** Same name, format and strings on both. The no-twin reply,
  verbatim: `No Veris twin is attached to this sandbox, so there is no receipt
  to read.`
- **MCP gating.** Daytona's plugin registers the `veris` MCP server and sets
  `veris_create_sandbox` and `veris_delete_sandbox` to `deny`,
  `veris_promote_sandbox` and `veris_reset_sandbox` to `ask`
  (`plugins/veris-config.ts`; the tool id OpenCode actually builds is P10).
  E2B's plugin has no config hook: no MCP server unless veris-sim registers
  it, and no gate on sandbox operations.
- **The platform's own prompt.** Daytona's system prompt states, for the whole
  tier, that unanswered hosts are blocked and a connection error is
  information. Measured false on E2B. Prefer the session's `egress:` line.
- **`VERIS_SANDBOX_ID`.** Injected by both SDKs when a twin is attached
  (`@veris-ai/daytona` `dist/index.js:678`; `veris-e2b` `src/sandbox.ts:424`).
  Whether it reaches the agent's shell is P4, not yet recorded. Not a tier
  signal on any platform.
- **gitSync.** Daytona's push failed 7 of 10 with `Host key verification
  failed` unless `DAYTONA_SSH_KNOWN_HOSTS` is set; E2B's bundle route has
  completed twice and has never been shown to carry a newly created file.
  Nothing a gate depends on rides on it.
- **`gpt-*` models.** Suspected, not measured (P12): OpenCode enables
  `apply_patch` and filters `edit`/`write` by id, so edits land on the host
  while `bash` runs in the sandbox.
