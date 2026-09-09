# An existing plugin-managed session

Read this before machine checks when the current tools or runtime context say a
plugin runs commands in a sandbox. This is separate from [hosted.md](hosted.md):
that workflow owns a remote test runner from a controlling machine; here the
plugin owns the execution sandbox and its attached twin. Missing Docker, a missing
CLI/key, or old `.veris/setup.json` alone establishes neither mode.

## Verify now, including on resume

For OpenCode, read [opencode.md](opencode.md) for provider discovery and available
interfaces. Establish the provider from current context, the twin id from a live
plugin tool, and the repository directory with remote `pwd` and
`git rev-parse --show-toplevel`. Confirm the expected code and base commit arrived;
a directory existing does not prove initial git sync succeeded. Record the current
OpenCode session id when supplied by `verisSkill`, provider, twin id, repository,
source commit, installed package versions, and **lifecycle owner: plugin**.

Reuse a binding already verified in this live session. Revalidate with the provider's
identity/receipt tools after reconnect, a relevant identity/configuration change, or
when the binding is uncertain after compaction. Saved metadata alone is not a live
binding. If the twin, session or source base changed, refresh the affected baselines
and dependent state/evidence. A transient failure is not an empty baseline.
An unattached session needs the provider's host credentials
and an environment with the required services, then a new/repaired provider session.
Name that prerequisite and stop; do not switch into CLI provisioning.

Once verified, these rules replace CLI execution and lifecycle instructions in
setup, build, fix, and their references. Application assertions and evidence from the
same execution still determine what is verified:

- Work with the sandbox's application tools, in the verified repository. Run the
  application's own command directly with existing interception. Do not nest
  `veris run`, a proxy, Docker, a provider CLI, or another sandbox around it.
- Keep repository reads, edits, tests, probes, seeding, receipts and git sync
  in this verified **parent session**. A child session is not this
  sandbox: do not test its host-HEAD checkout or use its twin as parent evidence.
  Subagents may only analyze supplied content when their session cannot provision
  resources; never give them repository or provider operations without an explicitly
  established shared sandbox/twin binding, including lifecycle hooks. Published
  OpenCode providers can provision on child idle even without a tool call, so do
  not launch OpenCode `task` subagents in those versions (see [opencode.md](opencode.md)).
  Bound reads and summarize long output in the parent instead.
- Reuse this twin. Skip `veris up`, environment creation, image/proxy setup,
  `--fresh`, promotion, reset and all teardown commands. Do not clear history to
  simplify a receipt. The plugin owns these resources; no `veris down` at finish.
- Discover the interface needed for the current operation before using it;
  reuse verified interface information. Bind every control operation to the current twin
  and service. CLI examples elsewhere describe the intended operation; use the
  verified session interface instead. A missing operation blocks verification that
  needs it; report that gap while continuing independent work. Do not guess endpoints.
- Preserve the provider's TLS environment, system trust, proxy and network settings.
  A cert failure under those defaults is a provider/twin finding. Do not disable
  verification, relax Python's strict certificate checks, patch production TLS
  code, or overwrite CA variables to make a smoke pass.

## Setup in this repository

Instead of setup steps 1–6, verify the session above, inspect the application's
vendor hostnames, and match them to the attached services. A missing service needs
a change to the environment selected by the plugin and a new provider session;
do not add a second twin. Read the required manuals and schema, discover seeded
credentials without printing secrets, and prove the smallest application flow
using the receipt procedure below and response/state assertions.

Then do setup steps 7 and 9 in the remote repository. In `NOTES.md`, record the
actual application command, dependencies, source revision, services, interface
names/locations, trust findings, versions, evidence and synchronization procedure.
Optional helpers are needed only for an explicitly requested audit or investigation.
When staging one in OpenCode,
read `veris-reference/scripts/record.sh` and `veris-reference/scripts/ledger.sh`
using `verisSkill`; stage each returned `content` unchanged into `.veris/bin/`
and verify its returned SHA-256 there. Use a provider-backed `write` when available,
or the remote `bash` recipe below when model filtering hides `write`/`edit`.
OpenCode's native `apply_patch` edits host files; it cannot stage or edit this
remote repository. Use the provider's `bash` for application edits too when the
remote editing tools are absent, then inspect the diff in the same sandbox.
Do not fetch helpers from GitHub or another release.
Check tools needed by the actual command in this sandbox; optional audit helpers
need `sh`, `git` and `jq`. Missing helpers do not block ordinary development.
Report any blocked dependency install that the requested work needs.

### Stage through remote bash

Use this recipe only when staging an optional helper. Send it through the provider's
`bash` in the verified parent session. Replace `<verified-repository>` with the verified remote path
(shell-quote it), `<helper-name>` with `record.sh` or `ledger.sh`, and `<sha256>`
with that resource's returned hash. Replace the entire `<exact-content>` line with
the returned content, retaining its final newline without adding a blank line.
Keep the heredoc delimiter quoted and choose one absent as a full line in the
content; shell variables, backticks and substitutions in the helper must stay
literal. Require a complete resource result; truncated content is not stageable.

```sh
(
  set -eu
  cd '<verified-repository>'
  mkdir -p .veris/bin
  veris_stage=$(mktemp .veris/bin/.helper.XXXXXX)
  trap 'rm -f "$veris_stage"' EXIT
  cat > "$veris_stage" <<'VERIS_HELPER_LITERAL'
<exact-content>
VERIS_HELPER_LITERAL
  if command -v sha256sum >/dev/null 2>&1; then
    veris_hash=$(sha256sum "$veris_stage")
  else
    veris_hash=$(shasum -a 256 "$veris_stage")
  fi
  if [ "${veris_hash%% *}" != '<sha256>' ]; then
    printf '%s\n' 'Veris helper hash mismatch; helper not installed' >&2
    exit 1
  fi
  chmod 755 "$veris_stage"
  mv "$veris_stage" '.veris/bin/<helper-name>'
)
```

This writes to a temporary remote file and installs it only after the hash matches.
If neither remote write nor remote bash is usable, or no SHA-256 utility exists,
report that helper's staging prerequisite. Do not substitute a host file operation.

### Persist setup observations

Keep step 9's source/build facts and artifact policy in `.veris/setup.json`, adding
`"execution": "plugin-session"` and a `session` object with the observations above.
These are observations, never authority to reuse a twin. Do not manufacture
`.veris/twin.yaml`: the plugin owns selection. On build/fix, verified session
metadata and `NOTES.md` replace that CLI file prerequisite. Verify or refresh an
optional helper before using it after an upgrade; it is not a setup prerequisite.

Step 8's file seeding, when needed, uses the discovered interface on this twin;
read back hashes, but skip baseline promotion. Finish with saved evidence and
change handoff below, leaving the session alive.

## Evidence from this run

The published OpenCode receipts are cumulative **views of a request log**, not
`veris run` receipts. Their counts are the length of the returned request array,
not a guaranteed all-time total; the API can bound that array. They omit trace ids,
times, tiers and bodies. The unfiltered tool identifies the twin; the service-only
form does not. Neither form accepts `since`. At zero total traffic the full form
also omits service names; use the provider discovery procedure rather than reading
an absent list as an empty environment. Never add invented arguments.

When using these cumulative receipts to attribute an application execution, use the
procedure below. One execution may include several assertions or retry scenarios;
do not create another evidence window for each claim or replay an already attributed
test of the final relevant code and conditions.

1. Finish seeding, diagnostic probes and other test runs first. Await background
   work. Read an unfiltered receipt to identify the twin, save its output, then a
   service receipt for each required service. Record the before count and displayed
   entries. Where raw trace access exists, capture the newest id per service too.
   A successful empty log establishes zero; a failed/ambiguous read does not.
2. Run only the intended application flow in the verified sandbox repository.
   Capture the exact command, exit status and response assertions. Record returned
   resource ids or a test correlation value. No concurrent suite, probe, seeding,
   health poll or control read belongs inside this window.
3. Read the unfiltered and required-service receipts again. The twin must still
   match. Compare before/after on that service; nonzero cumulative traffic alone
   proves nothing. Exclude `/veris/*`, canaries, provisioning and diagnostic calls.
   A hand-addressed vendor probe is still a probe, even with a non-control path.
4. Prefer raw trace entries after the per-service watermark, with tier `handler`
   or `fault`, and response/state assertions keyed by the application's returned ids.
   Save the existing result; read state manually only if the test did not establish
   the required outcome or the result is ambiguous. A test of injected failure needs
   evidence that the relevant fault occurred and the expected application outcome;
   a method/path/status summary cannot prove a duplicate write or fault phase.

A count increase is only supporting evidence: attribute the new application
entries to the isolated command and correlate the asserted response/state. Full
receipts show at most 20 entries per service, without a truncation notice;
service receipts show at most 50. If all entries needed to explain the delta are
not visible, the count plateaus/drops, history may have reset, traffic overlaps,
or identical old entries cannot be separated, obtain complete raw trace data via
the discovered interface. If that is unavailable, report **current-run attribution
unproven**, with the precise missing data. Do not reset the twin, subtract unrelated
traffic by guess, or turn the summary into a synthetic `veris run` receipt.
Preserve the reported interception mode, integrity and blind spots with the result.

Use the affected integration test and the repository's required checks. A suite whose
assertions and attributed traffic already establish the change needs no separate
verification flow. Do not overlap unrelated work in a cumulative-receipt window.
Optional `record.sh` and `ledger.sh` can support a requested audit, as described in
[proof.md](proof.md#optional-audit-helpers); neither verifies provider attribution
or is required for ordinary `fix` or `build` work.

## Hand back code and evidence

Save the cited evidence before idle timeout, reconnect or session deletion. Follow
`artifact_policy`: `pr-body` means render evidence into the handoff/PR text before
sync; `commit` means include sanitized evidence in tracked files; `local` needs an
explicit export to the host if it is to survive the sandbox. Ignored `.veris/bin/`
and `.veris/tasks/` files do **not** arrive through git sync by default.

Use the provider's `gitSync`, await its result and record the destination local
branch and source commit. Both plugins reserve `opencode/N` branches; do not edit
those locally while the plugin owns them. Verify the changed files and retained
evidence on the host when host access exists. A disabled/failed sync is unfinished
handoff, even if the tests passed. Export files through an available provider file
interface or give a concrete transfer prerequisite; do not claim local arrival.

If `gh` or GitHub access is unavailable remotely, return the exact draft PR body
and branch/commit for the host's GitHub workflow. Do not widen network restrictions,
copy a GitHub credential into the sandbox, or claim to have opened a PR. Do not
delete the session to end setup, build or fix.
