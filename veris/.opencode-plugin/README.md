# @veris-ai/veris-sim-opencode

The canonical [Veris skills](https://github.com/veris-ai/plugins/tree/main/veris/skills)
for OpenCode: `/veris:setup`, `/veris:build <request>`, `/veris:fix <request>`.
Setup proves the application's vendor traffic reaches a twin; build measures vendor
claims before designing; fix reproduces a failure before editing and proves it closed.

## Install

Add the skills package and **one** sandbox plugin to `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@veris-ai/veris-sim-opencode@latest",
    "@veris-ai/daytona-opencode@latest"
  ]
}
```

For E2B, replace the second entry with `@veris-ai/e2b-opencode@latest`. Set the
provider's host credentials and `VERIS_ENVIRONMENT_ID`, then restart OpenCode.
These are OpenCode plugins, not standalone `npx` executables. Record resolved
package and SDK versions from the installed manifests/lockfile; pin those npm
versions to reproduce a session. See the bundled [OpenCode reference](skills/veris-reference/opencode.md)
for credentials, E2B's optional host MCP configuration, trust and release limitations.

The reasoning loop runs locally and the sandbox plugin runs application tools
remotely. The skills' `verisSkill` tool reads entrypoints, references and helper
scripts from this installed package on the host, so a remote `read` never needs
access to a local npm-cache path. Setup copies helper content through the remote
write tool and verifies its hash. `veris/skills` remains the only maintained copy.
The adapter adds no MCP, changes no permissions or trust settings, and preserves
user-defined commands. Commands are engineer-invoked; no automatic skill paths
are registered.

`setup` verifies the active session before CLI/Docker checks. `build` and `fix`
revalidate the attached twin and source repository, run application commands with
existing interception, and retain the same evidence gates. Receipts are cumulative
and truncated: use before/after evidence and application response/state assertions,
and report missing attribution rather than claiming a run was observed. The plugin
owns cleanup. Finish with `gitSync`; ignored evidence needs an explicit handoff.
See [the shared session path](skills/veris-reference/session.md).

The skills can also be installed alone for a CLI-owned workflow. That workflow
requires the Veris CLI and its login; separately provisioned hosted test runners
still use [hosted.md](skills/veris-reference/hosted.md) and
[daytona.md](skills/veris-reference/daytona.md), as introduced by PR #47.

## Release path

Publish **@veris-ai/veris-sim-opencode** from this directory. The former source
name `opencode-veris` has no npm release; do not publish a second distribution.
The published 0.7.0 package predates this path and used `/veris-sim:*` commands.
This change needs a new skills release before `@latest` contains session support.
The source directory is now `veris/`, with no Git checkout/download step for users.

`prepack` copies `../skills` into the tarball. The release workflow installs locked
dependencies, runs repository and adapter/package tests, packs once, and publishes
that tested tarball with public access. Configure npm trusted publishing for this
scoped package and this repository's `release-opencode.yml` before release.
No provider source change is required for asset loading; TLS/control/receipt
capability limitations of the installed provider remain explicit in the reference.

For local validation, run `npm ci` here, then `sh ../../tests/opencode_plugin.sh`.
The test packs in an isolated directory and compares every canonical resource.
