---
name: fix
description: Fix a defect against the vendor's twin - reproduce the failure the issue describes through the repository's own code before designing, prove it closed against the twin, with a receipt, write the PR with what was verified and assumed. Takes an issue link or a prompt. Run when the engineer names this command.
argument-hint: "<issue link | prompt>"
disable-model-invocation: true
---

Fix the defect in the request that accompanied this invocation (a GitHub
issue URL or number, or free text). Not done until every gate below is met
and the PR says so.

**The tier.** Before the task, and before any subagent exists, settle where this
session runs. Call the tool that reports what the twin received, with no
argument. A header naming a twin — `Veris receipt — twin <id>` — is the
**hosted** tier: your commands already run inside a provisioned sandbox whose
egress was intercepted before your first turn. A tool that answers that no twin
is attached is a session without a trust anchor — stop, name `VERIS_API_KEY`
and `VERIS_ENVIRONMENT_ID`, say a new session is required, and write nothing.
No such tool is not hosted.

`VERIS_SANDBOX_ID` decides nothing: the container tier exports it per task.
Once the tool has said hosted, it is a convenient second reading of the same id.

Hosted: `.veris/session.md` must exist, its `tier:` must read `hosted`, and its
`twin:` must be this session's twin. It is written per session and does not
outlive one, so a missing or stale file is the expected case, not an error —
load the `setup` skill by name, run it now, then continue here. Everything
below reads two nouns, **the run command** and **the receipt**. On this tier
the run command is the repository's own, for whatever flow the task names,
run as it stands — that file's `run:` is the one setup proved reaches the
twin, the shape to follow, not the command to rerun. Its `receipt:` is the
tool, and the tool reports the session's whole history, so a gate that says
*from that run* means the service's count rose across it: read it before the
run as well as after. Its `control_url:` lines are where
every `/veris/*` call below goes; `lifecycle: session` means create nothing and
delete nothing; `staging:` (`npm` or `raw`, then the version staged) is where
`.veris/bin/` came from, and `unreachable` there means setup did not finish.
`egress:` says what a host the twin does not answer for looks like from here,
and decides what a network error proves: `open` — nothing; a vendor the twin
does not model is called for real, with real credentials, and only the receipt
says what arrived; `boundary-refused` — a refusal matching the recorded status
and first body line is the boundary, not the vendor, and means the host is not
mapped, while one that does not match is the vendor's own; `unreachable` — a
connection error is the boundary. `issue_and_pr:` (`sandbox` or `engineer`) is
read under the task.

A reference link you cannot open is not a gate you may skip: the gate text
below stands alone, and where it does not, stop.

Not hosted: no `.veris/run.sh` and no direct-tier `.veris/setup.json` → stop;
`setup` runs first. A `setup.json` with `"tier": "direct"` replaces `run.sh`:
run the flow directly against the wired sandbox and read the trace where a
gate reads the receipt ([direct.md](../setup/reference/direct.md)).

Settled once, here. State it as a fact in every subagent brief — a subagent
does not re-derive it, and may not carry the tool that would let it.

**The task.** A GitHub reference → `gh issue view <ref> --json title,body,comments`;
quote it. Where `.veris/session.md` records `issue_and_pr: engineer`, `gh` is
not usable here: ask for the issue text now and put the PR body in the
transcript at the end. The gates are unchanged; only where the text comes from
and goes is. Name the failure in one sentence: what the vendor did, what the
code did next. Anything the issue states about the vendor — what it
supports, why it fails, what a field means — is a **claim**, the diagnosis
included. Sandbox lifecycle and every `/veris/*` call:
[reference/twin.md](../veris-reference/twin.md).

**The diagnosis.** Before any sandbox: read the code path the issue names
and enumerate every distinct defect that could produce the symptom — the
vendor's failures and the repository's own (state lost between requests, a
queue, a cache, a race), which no twin can represent. The manual's fault
catalog is one hypothesis source, never the selector: the twin confirms a
diagnosis chosen from code evidence, it does not choose it.

**A run costs roughly turns × context, and every large output stays resident for
every turn after it.** The expensive mistake is not an extra call; it is pulling a
big response into the thread that then has to carry it. So where subagents exist,
delegate by default anything that reads wide or returns long — this survey, a
full test-suite run, any output past a screenful — and keep the answer, not the
transcript. Ask this one for candidate defects, each with its file and line.
Read small things inline: a data census, one projected table, a filtered trace.

**The boundary.** Name where the vendor boundary sits in this task. A
defect internal to the repository, with no vendor claim load-bearing: say
so, verify by the repository's own test conventions, and spend the twin on
one end-to-end confirmation of the changed flow instead of the full gate
sequence. That one confirmation is a floor, not a discount: a reduced path
that drove nothing through the twin has not spent less — it has left the
change unproven, and the flow the issue names is the one it skipped. Spend
the full gates where the task rests on what the vendor
does — the trigger is the boundary, never self-assessed obviousness.

**The base.** Before the first edit, pin what the change will be measured
against: `sh .veris/bin/record.sh base --task <id> --paths <the files the
diagnosis implicates>`. It writes the starting commit into
`.veris/tasks/<id>/record.json`, and Gate 4 reads it from there. Without
`--paths` it falls back to the whole source tree, which pins far more than the
task touches. Do this at the start, not at the gate — a base chosen once the
diff exists is chosen by the thing being measured. On the hosted tier
`.veris/bin/` is staged per session by `setup`; no staged scripts means setup
is unfinished, which is a stop. A claimed task id whose
`.veris/tasks/<id>/record.json` is absent is also a stop, not a resume: the
base died with the session that pinned it. One task is one session here.

## Gate 1 — the failure reproduced before the first source edit

0. `.veris/NOTES.md`, if present — what setup and earlier tasks already
   measured about this environment; do not re-measure it. Append anything
   measured in this task that outlives it.
1. `create_sandbox` (MCP), or `POST ${VERIS_API_BASE:-https://svc.api.veris.ai}/v1/environments/$VERIS_ENVIRONMENT_ID/sandboxes`
   with `{"ttl_minutes":60}`; then `get_sandbox` until `status` is `ready` —
   one sandbox for this whole task; keep its id and each service's `control_url`.
   Where `.veris/session.md` names a twin, that is your sandbox: read the id
   and each service's `control_url` from there, create nothing, and delete
   nothing at the end. A sandbox or proxy session kept alive from an earlier
   run is a net save — reuse it, reading from the ledger what per-run receipt
   lines would have shown.
2. `GET {control_url}/veris/manual` — the service's own notes, short, read
   whole. It is authoritative for exactly these: the statuses and codes a
   fault may inject, the `match` selector keys this service supports, its
   API versions and selector, and its credential and setup notes. It is
   **not** a catalogue of what the service implements — read no coverage
   claim into what it leaves out. The catalogue is
   `GET {control_url}/veris/operations` (`?surface=rest|graphql|mcp`, paths
   as templates): a method and path absent there is not served; one present
   is answered, not necessarily faithfully. A surface the fix rests
   on gets one probe, and what a refusal proves is in
   [reference/troubleshooting.md](../veris-reference/troubleshooting.md):
   some settle the question, most do not.
3. The state. A sandbox boots the environment's default state, and the code
   path needs rows in it — the customer an invoice references, the account a
   charge posts to. Take the census first — `GET {control_url}/veris/data`
   with no parameters is every table and its row count in one small
   response — then read the shape of only the tables that matter:
   ```sh
   curl --fail-with-body -sS "$CONTROL_URL/veris/schema" |
     jq -e --arg table "$TABLE" \
       '.properties[$table] // error("unknown table: \($table)")'
   ```
   A whole schema is far larger than any one task needs; project it.
   `GET {control_url}/veris/data?entity_type=<table>` then shows what is
   already there; seed what is missing, in the shapes the schema names:
   ```http
   POST {control_url}/veris/data
   {"data":{"<entity>":[{"<primary-key>":"test-owned-id","<field>":"value"}]}}
   ```
   File bytes are not rows: seed the rows first, then post the files
   through `/veris/files` ([reference/state.md](../veris-reference/state.md)).
   Ids come from the sandbox, never guessed and never carried from another
   sandbox. A call that fails because a row was absent is not the
   failure the issue describes. The state dies with its sandbox — resetting it, or
   keeping it: [reference/state.md](../veris-reference/state.md). On the
   hosted tier never `POST {control_url}/veris/reset` during a task: every
   reset clears `/veris/requests`, which is where the receipt is read from.
4. Make the failure happen. The vendor will not produce it on demand. A
   vendor-side defect: arm a `faults` row — `POST {control_url}/veris/data`
   with `{"data":{"faults":[…]}}`. The row names `method` and `path` (the
   vendor's, no host or query; `{id}` templates a segment), then what the
   issue reports: `"outcome":"error"` with an `error` object whose `status`
   the manual lists (`{"status":429,"code":"<listed>","headers":{"Retry-After":"2"}}`)
   for a refusal or a throttle; `"outcome":"hang"` with `"phase":"before"`
   for a request lost before the write, or `"phase":"after"` for a write that
   happened and was never answered — an `error` row carries `phase` too, a
   5xx after the write; `latency_ms` alone for slow. `remaining` spends it
   that many times, and a row without it fires on every match until
   `DELETE {control_url}/veris/data` with its id. Most SDKs retry a `5xx` or a connection error
   inside one call and the fault vanishes before your code sees it; check the
   client's retry setting, and arm a `4xx` to isolate the behaviour you mean
   to exercise. The full contract — `match` on body,
   query, path and GraphQL operation, the credential and clock rows — is in
   [reference/faults.md](../veris-reference/faults.md). A repository-side
   defect no fault can produce: reproduce it through the application's own
   state — and when the twin cannot represent it at all, that report is the
   Gate-1 outcome, not a reason to switch diagnoses. Either way, on the hosted
   tier first read the receipt and note the service's count — it reports the
   session's whole history, and this run has to raise it — then drive the
   **repository's own code path** — the endpoint, worker or handler the issue
   names, unchanged — through it under the run command: `.veris/run.sh` with
   `VERIS_SANDBOX_ID` set to this sandbox
   ([reference/proxy.md](../veris-reference/proxy.md)), or on the hosted tier
   the repository's own command for that path, run as it stands (`run:` in
   `.veris/session.md` is the shape, not the command).
5. Read the ledger: `GET {control_url}/veris/data?entity_type=<table>` and
   the trace. An injected fault's exchange is `tier=fault`, the traffic
   around it `tier=handler`, and your own `/veris/*` calls `tier=control` —
   ask for the tier the evidence is on rather than reading an unfiltered
   page of your own seeding ([reference/troubleshooting.md](../veris-reference/troubleshooting.md)).
   Not done with this gate until they show the outcome the issue describes —
   the duplicate row, the lost write, the wrong state — with ids and counts
   you can quote. On the hosted tier read the receipt again: the
   count noted in step 4 has to have risen, and the red run's requests are
   the ones that raised it.

The order is the evidence. The red run is observed against the
repository's unmodified code, before the first source edit; a red produced
afterward by stashing the fix satisfies nothing — it can no longer
challenge the diagnosis. The PR presents the red and green runs in the
order they actually happened.

If the failure will not reproduce, that is the finding: report what the
twin did instead, with the trace, and stop before changing code.
## Gate 2 — the identity the fix rests on

Before the fix keys, looks up, or dedupes on any field, read that field's
rule in `GET {control_url}/veris/schema` (the table's description). A field the vendor accepts
twice for distinct records is not an identity; a fix anchored on it trades
one failure for another. Name the field the fix rests on, and why it is
one, in the PR.

The gate binds on any identity, dedup key or external reference the fix
sends across the vendor boundary, however the code got it — computed,
copied from an input, reused from an id the caller already carries. Copying
does not discharge it: what the value leaves out has no row in the schema
to read, and the collision lives there. Prove it against the twin. Vary
each component of the identity independently — including an input that
omits one — drive them through the same path, and count the rows the vendor
stored: distinct inputs must have left distinct records. Fewer is the fix's
own defect, caught before it ships. The identity, what you varied and the
counts go in the PR beside the field. Questions and their asks:
[reference/twin.md](../veris-reference/twin.md).

## Implement

As the repository does it: its test conventions, its coverage gate, nothing
pointed at a sandbox, no vendor call changed to make a test pass. The
repository's full test gate runs once: backgrounded, no self-imposed
timeout, polled to completion, its result read before the PR is written.
Never kill a running suite to relaunch it; never report a result that was
not read.

## Gate 3 — the same failure, closed, with a receipt

Re-arm the same fault; drive the same code path through the run command
(`.veris/run.sh` with the same `VERIS_SANDBOX_ID`, or on the hosted tier the
same repository command as the red run); read the ledger again. **Not done until the receipt shows at least one
request to the service from that run and the ledger shows the outcome the
fix promises** — one row where there were two, the write recovered, the
state right. Red before, green after, same flow: that is the proof. On the
hosted tier the receipt is cumulative — the red run's requests are already in
it — so read the service's count before the green run, and *from that run*
means it rose.

One green proves one path. Before the PR, list every entry point that
reaches the lines you changed — grep the changed symbols for their callers,
and the constants those callers branch on, out to the endpoints, workers,
handlers and jobs that own them — and say which of them this run actually
drove. The ones it did not are not covered: they belong under *limitations
and risks*, named, with what a caller reaching the fix that way would still
get. A shared helper reached three ways and driven once is a fix for one
third of the defect. Callers are not the whole list: a branch that
duplicates the behavior rather than calling it — the same response handled,
the same request built inline, selected by a mode or type switch — cannot
appear in a grep for the symbol you changed. Search for those siblings,
name each one you found, and either drive it in the green run or put it
under *limitations and risks* with why it is out of scope. An unexercised
sibling reported as covered fails this gate. In a repository large enough
that this sweep spans many files, it is worth a subagent where one is
available: ask for the entry points, each marked driven or not-driven.

## Gate 4 — the measurements against the diff

Every measurement this task took is one row in the ledger, written when you take
it rather than reconstructed at the end — a ledger assembled after the code is
a description of the code, not a check on it. Before the PR:
`sh .veris/bin/ledger.sh --against-diff --task <id>` — no `--base`: it reads
the commit pinned at the start of the task. If it reports the base is unpinned,
that is the task's mistake, not the gate's; it does not get a base at gate time.

Each row ends as exactly one of four dispositions — the ledger's own tokens,
one line each:

- `ENCODED` — name the changed file and the symbol or decision honouring it.
- `NON_LOAD_BEARING` — carries a counterfactual: the different value this
  measurement could have taken without changing what the fix promises. If you
  cannot write one, it is load-bearing and this is not the row.
- `CONTRADICTED` — the change does what the measurement says is wrong. A gate
  failure.
- `UNRESOLVED` — never settled. A gate failure.

**A contradiction is the code's problem, not the report's.** Change the code.
`ledger.sh init` prints the field contract; the three layers a claim belongs
to, and the identity invariants Gate 2 binds on, are in
[reference/proof.md](../veris-reference/proof.md).

## The PR

Open a draft as the repository does — under `issue_and_pr: engineer`, put the
body in the transcript and say so. The body has three sections, in this shape;
a heading with nothing under it is information too:

- **What I verified, and how** — the failure, reproduced: the fault armed, the
  flow driven, the wrong outcome observed, before any code changed. The fix,
  through the shipping path: the same flow, green, from the boundary the task
  names, with the receipt from that run. What the vendor recorded: the before
  ledger, the after ledger, the `/veris/data` or `/veris/requests` read-back
  that shows the fix did what it claims, not a layer below it.
- **What I am assuming rather than verifying** — every behaviour the fix
  relies on with no measurement behind it, vendor documentation included, and
  why assuming it is acceptable. A measurement in the ledger that points the
  other way belongs here, stated, not omitted.
- **Limitations and risks** — what the fix does not cover; what a caller could
  still do wrong; what depends on a vendor setting this sandbox could not
  exercise.

Every task premise measured false is its own line in the body — the premise,
the probe, the answer — and is never restated as fact after that measurement,
in prose, code, or a name. Paste the sandbox id. Then `delete_sandbox` (or
`DELETE …/sandboxes/<id>`) — unless the session owns it, in which case delete
nothing. The same shape, as a template:
[reference/evidence.md](../veris-reference/evidence.md).

When a step needs it: [state.md](../veris-reference/state.md), [webhooks.md](../veris-reference/webhooks.md),
[trust.md](../veris-reference/trust.md) (a certificate or connection error
against a mapped host while others intercept), [troubleshooting.md](../veris-reference/troubleshooting.md).
Note anything the sandbox got wrong or lacked and give it to the engineer at
the end. Ask before sending repository code anywhere new. Never promote a
sandbox.
