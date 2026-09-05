# @veris-ai/veris-opencode

The canonical [Veris skills](https://github.com/veris-ai/plugins/tree/main/veris/skills)
for OpenCode: `/veris:setup`, `/veris:build <request>`, `/veris:fix <request>`.
Setup proves the application's vendor traffic reaches a twin; build measures vendor
claims before designing; fix reproduces a failure before editing and proves it closed.

## Install

After the renamed skills package is published, add it and **one** sandbox plugin
to `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": [
    "@veris-ai/veris-opencode@latest",
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

Publish **@veris-ai/veris-opencode** from this directory. This aligns the OpenCode
package with the `veris` plugin name in Claude and Codex. `veris/skills` remains the
canonical content; there is no separate OpenCode skill tree to maintain.

The published **@veris-ai/veris-sim-opencode** 0.7.0 package is the old name and
uses `/veris-sim:*` commands. After the new package's first release, replace the old
entry in your OpenCode `plugin` array with `@veris-ai/veris-opencode@latest`, restart
OpenCode, and use `/veris:*`. Remove the old entry from both project and global
configs if present: npm does not migrate a renamed package automatically, and the
two skills packages should not load together. The prior source name `opencode-veris`
was also unpublished and should be replaced if configured.

As checked on 2026-09-04, the new npm name is not published. The intended first
version is **0.7.3**, matching the other plugin manifests. Its initial publication
and trusted-publisher setup are release prerequisites; this PR does neither and
does not deprecate or republish the old package.

`prepack` copies `../skills` into the tarball. The release workflow installs locked
dependencies, packs once, runs repository and adapter/package tests against that
artifact, and publishes it with public access. Configure npm trusted publishing
for **@veris-ai/veris-opencode**, repository `veris-ai/plugins`, workflow
`release-opencode.yml`; the old package's publisher configuration does not apply.
No provider source change is required for asset loading; TLS/control/receipt
capability limitations of the installed provider remain explicit in the reference.

For local validation, run `npm ci` here, then `sh ../../tests/opencode_plugin.sh`.
The test packs in an isolated directory and compares every canonical resource.
