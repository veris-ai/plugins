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

Call the provider's identity/receipt tools again at every setup/build/fix entry and
after reconnect or compaction. Compare with the saved observations. If the twin,
session, or source base changed, take fresh baselines and redo dependent seeding and
measurements; never pair an old red with a new twin's green. A transient failure is
not an empty baseline. An unattached session needs the provider's host credentials
and an environment with the required services, then a new/repaired provider session.
Name that prerequisite and stop; do not switch into CLI provisioning.

Once verified, these rules replace CLI execution and lifecycle instructions in
setup, build, fix, and their references. Their evidence gates still apply:

- Work with the sandbox's application tools, in the verified repository. Run the
  application's own command directly with existing interception. Do not nest
  `veris run`, a proxy, Docker, a provider CLI, or another sandbox around it.
- Reuse this twin. Skip `veris up`, environment creation, image/proxy setup,
  `--fresh`, promotion, reset and all teardown commands. Do not clear history to
  simplify a receipt. The plugin owns these resources; no `veris down` at finish.
- Discover the available manual, schema, data, fault, trace and file interfaces
  before using them. Bind every control operation to the freshly verified twin
  and service. CLI examples elsewhere describe the intended operation; use the
  verified session interface instead. A missing operation blocks that claim or
  gate, not permission to guess an endpoint or weaken the evidence.
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
Stage the two canonical helper scripts from the installed package. With OpenCode,
read `veris-reference/scripts/record.sh` and `veris-reference/scripts/ledger.sh`
using `verisSkill`; write each returned `content` unchanged into `.veris/bin/`
using the remote write tool and verify its returned SHA-256 there. Use
`sha256sum` or `shasum -a 256`. Do not fetch helpers from GitHub or another release.
Check `sh`, `git`, `jq`, and the application's runtime in this sandbox. Missing
helpers/tools are a concrete prerequisite; report any blocked dependency install.

Keep step 9's source/build facts and artifact policy in `.veris/setup.json`, adding
`"execution": "plugin-session"` and a `session` object with the observations above.
These are observations, never authority to reuse a twin. Do not manufacture
`.veris/twin.yaml`: the plugin owns selection. On build/fix, verified session
metadata plus staged scripts and `NOTES.md` replace that CLI file prerequisite.
Re-stage helpers after a package upgrade or if hashes differ.

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

For each smoke, red, identity case and green:

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
   or `fault`, and response/state reads keyed by the application's returned ids.
   Save the request/response or stored outcome the gate requires, after the run.
   An injected-failure gate needs the fault exchange and the reproduced outcome;
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

For fix, keep the same pinned-source record and measurement ledger. Wrap the
application command in `record.sh red/green --task ... --expect ... -- <command>`
in the remote repository. Store the raw before/after receipt outputs and state or
trace alongside the record. `record.sh` records commands and source/build hashes;
it does not verify provider receipt attribution. Red precedes source edits, green
uses the same failure and flow on the same twin, and Gate 4 must still pass. Finish
the full suite before taking Gate 3's baseline; do not use `--fresh` here.

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
