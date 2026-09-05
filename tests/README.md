# Validation

Run the repository checks with Node 20+ and `git`, `sh`, `jq`, `tar`, and npm:

```sh
npm ci --prefix veris/.opencode-plugin
sh tests/ledger_repository.sh
sh tests/record_argv.sh
sh tests/opencode_plugin.sh
```

The adapter tests compose both providers' remote file-tool boundaries in both
orders, retain user config, read every canonical reference/helper, check script
hashes, and import an isolated packed artifact through its public npm export.
They do not create a remote sandbox. The release workflow sets
`VERIS_TEST_TARBALL` to test the exact artifact it will publish.

`opencode_providers.test.mjs` additionally exercises **published provider code**:
Daytona's config hook and both receipt renderers. It stubs the SDK type guard and
session handles; passing it is not live network, TLS or git-sync validation.
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
identity, and configuration composition. Record resolved versions when testing
newer releases; do not treat a source checkout as a published package.

Live acceptance requires separate sessions with each provider and an attached
environment covering the fixture's vendor. Run setup; build a vendor-reaching
feature; reproduce and fix a meaningful failure with source pinned before red.
Capture per-service receipt baselines and raw traces/state, prove a diagnostic
probe cannot satisfy an application gate, and recheck identity after reconnect.
Finish with gitSync and verify code and retained evidence on local `opencode/N`.
Never mix the two providers in one config or delete plugin-owned resources from
the skills. Record missing control access or TLS/release prerequisites precisely.
