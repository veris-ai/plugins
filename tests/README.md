# Validation

Run the repository checks with Node 20+ and `git`, `sh`, `jq`, `tar`, npm,
`sha256sum` and `shasum` (both checksum branches are exercised):

```sh
npm ci --prefix veris/.opencode-plugin
sh tests/ledger_repository.sh
sh tests/record_argv.sh
sh tests/skill_version_claims.sh
sh tests/opencode_plugin.sh
```

`skill_version_claims.sh` denies three ways a skill document freezes a fact about a
moving release: a package specifier pinned to a version or a `<version>` placeholder
instead of `@latest`, a recorded resolution of the `latest` tag, and a command form of
the `veris-daytona` executable that `@veris-ai/daytona` no longer ships. Point
`SKILL_DOCS` at another copy to check it.

The adapter tests compose both providers' remote file-tool boundaries in both
orders, retain user config, read every canonical reference/helper, check script
hashes, and import an isolated packed artifact through its public npm export.
The documented remote bash recipe runs with write/edit absent and separate host,
parent and child directories. It checks both checksum utilities, shell-literal
content and rejection of corrupted content without replacing an installed helper.
They do not create a remote sandbox. The release workflow sets
`VERIS_TEST_TARBALL` to test the exact artifact it will publish.

`opencode_providers.test.mjs` additionally exercises **published provider code**:
Daytona's config hook, both receipt renderers and both idle-event hooks. It stubs
the SDK type guard, session handles and git queue; passing it is not live network,
TLS or git-sync validation. The idle checks show a child id reaches `getSandbox`
without a child tool call; the fake manager supplies the separate source/twin.
To reproduce the 2026-09-04 audit, obtain these npm releases with `npm pack`:

- `@veris-ai/daytona-opencode@0.2.1`
- `@veris-ai/e2b-opencode@0.1.1`

Extract each into `<artifacts>/daytona/package` and `<artifacts>/e2b/package`.
Make the adapter's installed Zod dependency resolvable from `<artifacts>/node_modules`
(for example with a local symlink), then run:

```sh
VERIS_PUBLISHED_PACKAGES=<artifacts> bun test tests/opencode_providers.test.mjs
```

Bun resolves the released providers' extensionless imports. No provider SDK is
executed; no keys are needed. The tests cover twin discovery, the absence of
service names at zero total traffic, service-filtered zero receipts, absent
attachment, control traffic in counts, 20/50-entry truncation, count plateaus, replacement
identity, child idle session lookup, and configuration composition. Record resolved versions when testing
newer releases; do not treat a source checkout as a published package.

Live acceptance requires separate sessions with each provider and an attached
environment covering the fixture's vendor. Run setup; build a vendor-reaching
feature; reproduce and fix a meaningful failure with source pinned before red.
Capture per-service receipt baselines and raw traces/state, prove a diagnostic
probe cannot satisfy an application gate, and recheck identity after reconnect.
Exercise helper staging and edits with a GPT model that hides write/edit. Keep
tests and repository/twin operations in the parent; do not start task subagents
with the inspected providers. Finish with gitSync and verify code and retained
evidence on local `opencode/N`.
Never mix the two providers in one config or delete plugin-owned resources from
the skills. Record missing control access or TLS/release prerequisites precisely.
