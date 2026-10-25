---
name: add-your-hosted-agent
description: Use when putting an agent that runs on your own servers or cloud on a Veris Bench bench as a Hosted endpoint candidate, when registering a new version of it, or when its bench attempts show connection-check failures, empty or mixed-up replies, or no model calls for the grader.
argument-hint: "[bench id]"
---

# Add your hosted agent to Veris Bench

Take an agent that you run and expose at a URL to a registered **Hosted
endpoint** candidate on a Veris Bench bench, let the grader see its model calls,
and prove it works with a smoke trial. Veris runs nothing of yours: the bench
calls your endpoint once per conversation turn.

**The agent is the constant.** The only code you add is `bench_tracing`, one
file, wired in at startup and around each request. Change nothing else in the
agent, and say so in your report if you had to.

A smoke attempt that is `completed` does not prove the integration works. An
agent whose replies never reach the bench, or whose model calls the grader
cannot see, still completes. "Done means" below says what to check.

Read `reference/api.md` before step 1 and `reference/tracing.md` before step 7.

## Inputs

Collect these before you change anything. Ask the user for what is missing.

| Input | Where it comes from |
| --- | --- |
| `VERIS_API_KEY` | Environment variable, starts with `vbk_`. Only a person can issue one: console, **Overview**, **API keys**, **Issue**. Never print it or write it to a file. |
| `BENCH_API` | Default `https://bench.api.veris.ai/v1`. Use another only when the user gives one. |
| `BENCH_ID` | The skill's argument, if the user gave one. Otherwise ask, or list their benches and have them choose. |
| Endpoint URL | The deployed agent's public `https://` URL, one per version (a tag, a revision URL, a versioned path). Not `localhost`, not a private address. |
| Endpoint auth | How the endpoint authenticates callers, such as a bearer token. Its value goes in the bench's candidate-env as a secret, never in the candidate file. |
| `BENCH_TRACE_KEY` | A push-only Veris Bench key: it can send traces and nothing else. A person issues it in the console's **API keys**. It goes in the deployment's secret store, next to the agent's other secrets. Never use `VERIS_API_KEY` for this. |

## Steps

1. **Check access.** Read the bench. `access` must be `write`
   (`reference/api.md`, "Access").
2. **Check the fit.** Read the bench's world and tasks (`reference/api.md`,
   "World"). A hosted agent does not get the bench's twins: each task runs with
   no world, and the agent calls whatever services it is configured with.
   - If the agent calls real systems, tell the user before any trial: every
     attempt makes real requests and writes, costs and rate limits multiply by
     the trial's `parallel`, the grader gets no record of those calls, and
     results won't repeat exactly. Go on only when the user agrees.
   - If the tasks need the bench's twins, the agent has to use a twin sandbox
     that Veris sets up (`reference/api.md`, "Twin sandbox"). Its attempts share
     one world, so trials run one attempt at a time.
   - A turn must answer within 120 seconds (180 for a streamed reply). Tell the
     user if the agent can take longer.
3. **Read the endpoint's contract.** From the repository if you have it,
   otherwise from the user. Write down: method and path; the request field for
   the user's text; how the agent keeps a conversation (a session id it returns,
   or the whole history in each request); the reply's field, or its streamed
   event names; the auth header. Confirm it with one `curl` to the deployed
   URL, with the auth secret from your environment, and a second one without
   the auth header: that one must be refused. If it isn't, tell the user before
   going on: the endpoint is open to anyone.
4. **Store the endpoint's secret** in the bench's candidate-env, under a name
   that belongs to this agent (`FENWICK_ORDERS_TOKEN`, not `TOKEN`), and refer
   to it from the channel's headers as `${env:NAME}` (`reference/api.md`,
   "Secrets"). A raw token in a header is refused.
5. **Write `bench/hosted-candidate.json` and register it**
   (`reference/api.md`, "Register"). It holds no secrets, so it can be
   committed, and CI can reuse it with a new URL.
6. **Run the connection check** (`reference/api.md`, "Connection check").
   Send one request first to wake a cold endpoint. Fix what the `stage` names
   and run it again until `ok` is true.
7. **Let the grader see the model calls** (http endpoints only; skip for ws and
   voice). Copy `reference/bench_tracing.py` or `reference/bench_tracing.mjs`
   into the agent, wire it in as `reference/tracing.md` says, and check it
   locally there. Then deploy it with `BENCH_TRACE_KEY` set, if the user gave
   you a way to deploy; otherwise the user does, and you wait. If you don't have
   the agent's code, give the user `reference/tracing.md` and go on; the grader
   then reads only the transcript.
8. **Run a smoke trial and verify it** (`reference/api.md`, "Smoke trial" and
   "Verify"). Two tasks, no personas, one repeat. When nothing is pending,
   check every attempt against the table below. Each row that fails is an
   integration bug: find the cause, fix it, redeploy, re-run the candidate in
   the same trial, and check again.
9. **Report** (format below).

## Done means every smoke attempt shows this

| Check | Where to read it (`reference/api.md`, "Verify") | If it fails |
| --- | --- | --- |
| It ran | `status` is `completed` | Read `error`. A failure before the first turn is the URL, the auth secret or the channel. |
| The agent answered | `turns` is 2 or more, and the transcript has agent replies that answer the question | Field mapping (step 3), or the agent errored on the turn: read your own server's logs. |
| The grader sees the model calls | `agent_trace_reason` is `null`, and `agent_trace.json` has `llm_calls` above 0 | `reference/tracing.md`, "If the grader sees nothing". `judge_disabled_trace` means the bench's grader doesn't read traces: skip this check. On ws or voice, or without step 7, `hosted_candidate` is expected: say so in the report. |
| The agent used its tools | `tool_calls` above 0 if the agent has tools, and its tool results in `agent_trace.json` are not errors | Read the tool results; a connection error means the agent can't reach a service it calls. |
| One conversation per attempt | Each attempt's transcript and trace hold only its own question | The agent keys conversation state wrongly. Attempts run in parallel against one endpoint. |

`passed` is not on this list. Whether the agent passes a task measures the
agent, not the integration.

## Traps that look like success

| Symptom | Cause | Fix |
| --- | --- | --- |
| Connection check: `probe`, `ReadTimeout` | The endpoint was starting a cold instance. | Send one request, then check again. |
| Trial creation refused: a value looks like a raw credential | A token typed into `headers` or the URL. | Candidate-env secret and `${env:NAME}` (step 4). |
| Agent replies are empty | The reply field or streamed event names don't match the endpoint. | Match `response` in the candidate file to the endpoint. |
| `hosted_candidate` though tracing is wired | Spans went to a trace other than `X-Veris-Traceparent`'s, arrived more than 10 seconds after the conversation, or `BENCH_TRACE_KEY` is unset in the deployment. | `reference/tracing.md`, "If the grader sees nothing". |
| `trace_fetch_failed` | A span the agent sent is malformed. | Use the OpenInference instrumentor's spans, unedited. |
| One attempt answers another's question | Conversation state keyed by something other than the session id. | Key it by the session id the bench sends, or send history (`request.history`). |
| Results differ between identical attempts | The agent changed data in a real system the next attempt read. | Reset the data, or use a twin sandbox (step 2). |
| A trial mixes two versions | The URL started serving a new version mid-trial. | One URL per version; a new version is a new candidate. |

## Report to the user

- The files you added or changed, one line each.
- The endpoint URL, candidate id and trial id, and the console link
  `https://benchmark.veris.ai/benchmarks/<bench id>?trial=<trial id>`.
- For each smoke attempt: the five checks, and `passed`.
- What the user still has to do: deploy the tracing change, issue or store
  `BENCH_TRACE_KEY`, or anything else you couldn't do.
- Every fix you made after the first smoke run, and why.
- Next: a full trial, as on https://docs.veris.ai/run-a-trial, and for a new
  version, a new candidate with the new URL in the same trial.
