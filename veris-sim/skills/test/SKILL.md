---
name: test
description: Run the repository's tests against the vendor's twin through veris-proxy - the test named with the command, or every test that reaches the vendor when none is named - and report per test what the twin received, so a green that never left the process is not taken for proof.
argument-hint: "[test file | name pattern | -- command]"
disable-model-invocation: true
---

Run tests through the twin. The request that accompanied this invocation
names a test — a file, a name pattern, or a full command after `--` — or
names nothing. No `.veris/run.sh` and no direct-tier `.veris/setup.json` → stop; `setup` runs first. A `setup.json` with `"tier": "direct"` replaces `run.sh`: run the flow directly against the wired sandbox and read the trace where a gate reads the receipt ([direct.md](../setup/reference/direct.md)). Read
`.veris/setup.json`: `test_command` is the runner the repository uses.

## 1. What to run

- **Named.** Map the reference onto that runner, never onto another: a file
  → `<runner> <file>`; a pattern → the runner's own name filter (`jest -t`,
  `pytest -k`, `go test -run`); text after `--` → verbatim.
- **Nothing named.** Candidates are `test_command`, plus every test file
  that reaches the vendor and is not already in it: it imports the vendor's
  client or SDK, names its hostname, or lives under `integration`/`e2e`.
  Find them with grep; do not run yet. A file whose only contact with the
  vendor is a mock is not a candidate. State the list in one line, then run.

## 2. Run

One run per candidate, through `.veris/run.sh` so the receipt is per test:
`.veris/run.sh -- <runner> <test>`. Flags before `--` pass through —
`--strict` proves nothing reached the real internet, `--require-service
<name>` makes the count the verdict. Each run deploys a fresh sandbox; with
`VERIS_SANDBOX_ID` set it attaches to that sandbox instead, so state seeded
and faults armed there are what the test meets
([reference/proxy.md](../veris-reference/proxy.md)). Exit codes: the
runner's own; `3` — the run reached the twin with nothing; `4` — a required
service or host is missing.

## 3. Report

One row per test: test · result · receipt (`<service> <count>`) · verdict.

- green, receipt names the service — **proven against the twin**.
- green, receipt empty (exit `3`) — **never reached the vendor**; say what
  answered instead (the mock, the stub, the skipped case). Not proof.
- red — the failure, with what the twin holds: rerun once with
  `VERIS_SANDBOX_ID` set to a sandbox you created, then `GET
  {control_url}/veris/requests` and the entity's `/veris/data`
  ([reference/twin.md](../veris-reference/twin.md)), and quote the rows.

**Not done until every candidate has a verdict and the report says which
tests reached the twin and which did not.** Change no test and no source: a
red here is a finding for `fix`, a mocked suite is a finding for the
engineer. Never promote a sandbox. Ask before sending repository code
anywhere new.
