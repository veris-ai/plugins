---
name: add-your-agent
description: Use when putting the agent in this repository on a Veris Bench bench as a "Your image" candidate, when updating that candidate to a new version, or when its bench attempts show empty replies, failed tool calls, no model calls for the grader, or never reach the bench's twins.
argument-hint: "[bench id]"
---

# Add your agent to Veris Bench

Take the agent in this repository to a registered **Your image** candidate on a
Veris Bench bench, and prove it works with a smoke trial.

**The agent is the constant.** Add one server file, a Dockerfile and a
candidate file beside the agent. Change the agent's own code only when there is
no other way, and say so in your report.

A smoke attempt that is `completed` does not prove the integration works. An
agent whose database calls all fail, or whose model calls the grader cannot
see, still completes. Step 9 says what to check.

Read `reference/api.md` before step 1 and `reference/image.md` before step 2.

## Inputs

Collect these before you change anything. Ask the user for what is missing.

| Input | Where it comes from |
| --- | --- |
| `VERIS_API_KEY` | Environment variable, starts with `vbk_`. Only a person can issue one: console, **Overview**, **API keys**, **Issue**. Never print it or write it to a file. |
| `BENCH_API` | Default `https://bench.api.veris.ai/v1`. Use another only when the user gives one. |
| `BENCH_ID` | The skill's argument, if the user gave one. Otherwise ask, or list their benches and have them choose. |
| Registry | A repository prefix Docker can push to, such as `ghcr.io/<org>`. |
| Model keys | The secrets the agent reads, such as `OPENAI_API_KEY`. They go in the bench, never in the image or the repository. The user adds a missing one in the console, unless it is already in your environment. |

## Steps

1. **Check access.** Read the bench. `access` must be `write`. If it is
   `read`, stop and tell the user why (`reference/api.md`, "Access").
2. **Read the agent, without editing.** Write down: language and entry point;
   the function that runs one conversation turn and how it keeps history; the
   model SDK and its installed version; every external service it calls and
   where each address or DSN comes from (variable, config file or a literal);
   every secret it reads; and files it opens by a relative path. Check the SDK
   against "Telemetry" in `reference/image.md` now: an unsupported version
   records no model calls and says nothing.
3. **Read the bench's world.** List its services (`reference/api.md`,
   "World"). Match each service the agent calls to a twin. Tell the user about
   any service the agent calls that has no twin: those calls reach the real
   vendor, unless Veris turned on the gateway for the bench.
4. **Add the server file**, `bench_server.py` or `bench_server.mjs`, from the
   pattern in `reference/image.md`. It wraps the agent's turn function, keeps
   one conversation per session id, serves `/health`, and listens on
   `0.0.0.0:8008`. Use http. Use ws only if the agent already speaks
   WebSocket.
5. **Point the agent at the twins, in the server file.** Before the agent's
   modules load, copy each twin's address from `VERIS_DS_SERVICE_URLS` into
   the setting the agent already reads. Apply the client fixes in
   `reference/image.md`, "Twins".
6. **Write the Dockerfile and `.dockerignore`** from `reference/image.md`. If
   the repository has a Dockerfile, reuse it when it can run the server.
7. **Check locally.** Build for `linux/amd64`, run it, and send `/health` and
   one turn (`reference/image.md`, "Local check"). Fix anything that fails
   here before you push.
8. **Push and register.** Push, pin by digest, run `check-image`, save a
   registry login if needed, make sure each secret is in the bench's
   candidate-env, write `bench/candidate.json`, and register the candidate
   (`reference/api.md`).
9. **Run a smoke trial and verify it.** Two tasks that need the agent's
   tools, no personas, one repeat. When nothing is pending, check every
   attempt against the table below. Each row that fails is an integration
   bug: find the cause in its artifacts, fix it, push a new digest, update the
   candidate, re-run it in the same trial once nothing is pending, and check
   again.
10. **Report** (format below).

## Done means every smoke attempt shows this

| Check | Where to read it (`reference/api.md`, "Verify") | If it fails |
| --- | --- | --- |
| It ran | `status` is `completed` | Read the end of `error`: it holds your container's last log lines. |
| The agent answered | `turns` is 2 or more, and the transcript has agent replies | Wrong path or field mapping, or the server crashed on a turn. Read `candidate.log` and `transcript.jsonl`. |
| The grader sees the model calls | `agent_trace_reason` is `null`, and `agent_trace.json` has `llm_calls` above 0 | See "Telemetry" in `reference/image.md`. `agent_trace_reason` alone is not enough: it is `null` when the trace holds no model call. `judge_disabled_trace` means the bench's grader doesn't read traces: not a bug, skip this check. |
| The agent used its tools | `tool_calls` above 0 if the agent has tools, and the tool results in `agent_trace.json` are not errors | A tool error that names a connection or a certificate is step 5; read "Twins" in `reference/image.md`. |
| It reached the twins | each twin the agent uses received at least one request from it (`reached` in the Verify command) | The agent is still pointed at its own default address. Redo step 5. Don't use `ledger_summary` counts for this: they include requests the platform makes. |

`passed` is not on this list. Whether the agent passes a task measures the
agent, not the integration. Two attempts say little about quality; a full trial
does.

## Traps that look like success

| Symptom | Cause | Fix |
| --- | --- | --- |
| Node agent: every database tool fails, and the log has a `pg` SSL warning | node-postgres treats the twin DSN's `sslmode=require` as `verify-full`, and the twin's certificate is self-signed | Append `uselibpqcompat=true` to the DSN in the server file |
| Node agent: `agent_trace_reason` is `no_spans_received` | The trace hook writes into the working directory, which the run user can't write | The run user owns the app directory (`chown`) |
| Node agent: `llm_calls` is 0, and `candidate.log` has no `veris-otel-node: instrumented OpenAI` line | The `openai` package is older than 5 | Upgrade `openai` to 5 or later, and update the lockfile so the image build installs it |
| The attempt fails within a minute, `exec format error` or a pull error | An arm64 image built on Apple Silicon, or the bench can't pull it | `--platform linux/amd64`; run `check-image` |
| Agent replies are empty | `image.path` or the response field doesn't match the server | Match `bench/candidate.json` to the server |
| Tools fail only on the bench | A literal address, or a variable the bench doesn't set | Step 5 |

## Report to the user

- The files you added or changed, one line each.
- The image reference, candidate id and trial id, and the console link
  `https://benchmark.veris.ai/benchmarks/<bench id>?trial=<trial id>`.
- For each smoke attempt: the five checks, and `passed`.
- Any change to the agent's own code or dependencies, and why.
- Every fix you made after the first smoke run, and why.
- Next: a full trial, as on https://docs.veris.ai/run-a-trial, and for a new
  version, a new candidate in the same trial.
