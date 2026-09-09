---
name: build
description: Build a feature using Veris to answer relevant service questions and test the changed application. Reuse normal development tests and report their results. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Build the requested feature. Use the twin to answer questions that affect the change
and exercise the application. Reuse evidence from normal development: once the required
behavior is covered and passes, finish. Investigate further when a failure or a
specific unanswered requirement warrants it.

For a change with no meaningful vendor interaction, skip Veris setup and twin work;
use the repository's validation and state that scope in the result.

## Use the working setup

Read `.veris/NOTES.md` for the saved application command and useful observations.
Reuse them unless the relevant code, service configuration or evidence has changed.
Run `setup` when the needed wiring or handoff is missing or broken.

In a plugin-managed session, follow
[session.md](../veris-reference/session.md): use the verified remote repository,
attached twin and provider tools. Reuse a binding established in this live session;
revalidate after reconnect or a relevant identity change. Provider execution replaces
the CLI commands below. Leave plugin-owned resources alive.

For CLI-owned work, use `.veris/twin.yaml` and the saved command. Reuse this task's
sandbox; `veris up` creates one if needed. Budget its TTL when creating it; an existing
sandbox cannot be extended. Check expiry before work that may outlast it.

An unavailable twin blocks verification that needs it. Report the concrete error;
independent code work and local checks can continue. Retry only when the error suggests
a recoverable condition or something changed. Do not report unrun checks as passed.

## Understand and implement

Read the issue (`gh issue view <ref> --json title,body,comments` for GitHub) or the
supplied prompt. Identify the requested behavior, its caller and relevant service
dependencies. Inspect existing application code and tests before designing a new flow.

Use the cheapest twin interface that answers an unresolved question affecting that
design. [twin.md](../veris-reference/twin.md) maps questions to the manual, schema,
operation list and data. Fetch the manual with
`veris sandbox services manual <twin> --raw` when credentials, API versions or fault
details are needed; read the applicable sections. A direct twin probe is useful
discovery. A test through the application can answer the same question while also
checking the implementation. Reuse an answer already established for these conditions.

Seed the state the feature needs using [state.md](../veris-reference/state.md).
Inspect the relevant owner/time window rather than assuming the default seed fits.
Use ids from this sandbox. A fully booked fixture, for example, does not disprove a
feature that books another date; do not change the requested behavior to fit the seed.

Implement using the repository's conventions and extend the relevant test. When the
feature changes failure handling, use [fault injection](../veris-reference/faults.md)
for the relevant condition. For retry, idempotency or identity changes, include the
applicable duplicate, distinct-operation and recovery cases in the affected test;
[proof.md](../veris-reference/proof.md#retry-and-identity-changes) has focused recipes.
Investigate an unanswered claim when it would change a decision, without postponing
all source edits until every possible vendor question has been catalogued.

Exercise the caller promised by the task. For an optional feature, test the new
argument/flag and preserve required existing behavior. Cover relevant alternate
dispatch branches when they can change that outcome. A test-only path that normal
callers never reach does not establish the feature works for them.

## Test the changed application

Prefer the repository's affected integration test, run with the command from
**How to run**. For a CLI container, its shape is:

```
veris run --patch-bundled-cas --require-service <twin> <saved mounts and variables> --receipt <file> -- <affected test or flow>
```

Use the edited source or a build produced from it. A wrong mount can execute the
image's old baked code; use the verified mount/build recipe. For hosted execution,
use the saved [provider command](../veris-reference/hosted.md). Keep production vendor
hostnames and credentials; interception belongs outside the application. For an app
wired without the proxy, use its existing production URL variables as described in
[direct.md](../veris-reference/direct.md). Never weaken TLS or change a vendor call
just to make a test pass.

The test must assert the expected response or persisted outcome, and its receipt or
attributed trace must show the relevant application traffic reached the twin. Existing
assertions that read the outcome are sufficient; do not repeat them with manual data
reads. If the result is unclear, inspect the relevant rows by returned ids or the
trace for this run. See [run.md](../veris-reference/run.md) for receipt/exit semantics
and [webhooks.md](../veris-reference/webhooks.md) when a callback is part of the task.

An existing execution counts if it tested the final relevant code/build and conditions.
One suite can cover several requirements; a retry case can make multiple calls in one
test. There is no required second successful run or separate proof phase. Honor the
repository's required checks, reuse their evidence, and rerun affected checks after
changes or failures.

If the assertions fail, change the implementation or correct the diagnosed setup
problem. If required behavior remains untested, report that gap. A successful process
exit or unrelated twin traffic alone is not verification of the change.

## Finish

Summarize what changed, the test/command and outcome with an existing evidence
reference, and material limitations. [evidence.md](../veris-reference/evidence.md)
shows the short form. Note any task premise disproved by the investigation when it
affected the solution. A known contradiction is a defect to resolve, not an assumption.

Follow the repository's PR convention; open a draft when that is the requested
handoff. Without a PR-capable remote, save the description locally and say no PR was
opened. Git history, task ids and the optional [audit helpers](../veris-reference/proof.md#optional-audit-helpers)
are not prerequisites for working on code. Do not initialize Git or add a remote
implicitly. Use available package/version metadata if useful for debugging; it is
not a separate completion requirement.

Save cited redacted evidence before cleanup, honoring `.veris/setup.json`'s existing
`artifact_policy`. Update **How to run** if you repaired it. Use `veris down` only for
a CLI-owned task sandbox; hosted work follows its provider cleanup, and plugin sessions
use [change sync](../veris-reference/session.md#hand-back-code-and-evidence).
Do not promote from this command. Ask before sending repository code anywhere new.
