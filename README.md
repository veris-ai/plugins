# Veris plugins

## veris-sim

Skills for coding agents that test an application against Veris, whose
stateful twins stand in for the external services the application calls. An
**environment** names which services; `VERIS_ENVIRONMENT_ID` points at one.
A **sandbox** is one running deployment of an environment: `veris-proxy`
deploys one per run, reroutes the application's outbound traffic into it from
outside the process — the application is never modified — and prints a
receipt of what the sandbox received.

| Skill | Use when |
| --- | --- |
| [`setting-up-veris`](veris-sim/skills/setting-up-veris) | the repository cannot yet run its tests under `veris-proxy`. Checks the prerequisites, derives a test image, writes the run command into the repository as `.veris/run.sh`, and proves the wiring with one smoke run. |
| [`discovering-vendor-behavior`](veris-sim/skills/discovering-vendor-behavior) | a design depends on what the vendor does — on a retry, a duplicate, a lost response, a limit. Reads the service's manual and schema, probes the sandbox, makes the failure happen, and records what was measured. |
| [`integration-testing`](veris-sim/skills/integration-testing) | a change that calls an external service needs exercising. Arranges state, arms a fault, drives the application through the proxy, reads back what the sandbox recorded, and shows the change red before and green after. |

The plugin also registers the `veris` MCP server — `$VERIS_API_BASE/mcp`
(default `https://api.veris.ai`) with `X-API-Key: $VERIS_API_KEY` from the
environment — so the sandbox tools are available as soon as the plugin is
enabled. Sandbox mechanics — state, seeding, faults, the clock, reset,
callbacks, diagnosis — are documented once, under
[`veris-sim/skills/integration-testing/reference/`](veris-sim/skills/integration-testing/reference/).
Each service in a sandbox serves what is specific to it: `/veris/manual` and
`/veris/schema`.

### Install

Claude Code:

```
/plugin marketplace add veris-ai/plugins
/plugin install veris-sim@veris
```

Any other agent, skills only:

```
npx skills add veris-ai/plugins
```

This repository is internal to the organization; `gh auth setup-git` lets
Claude Code refresh the marketplace in the background without prompting.
