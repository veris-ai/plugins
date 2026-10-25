# Bench API calls for a hosted agent

Most coding agents run each command in a new shell, so a variable you set in
one command is gone in the next. Start every command with these lines, and
write ids into later commands as literal text after you print them:

```bash
BENCH_API=${BENCH_API:-https://bench.api.veris.ai/v1}
bench() { curl -s -H @<(printf 'Authorization: Bearer %s\n' "$VERIS_API_KEY") "$@"; }
BENCH_ID=bench_...
```

`bench` is `curl` with the key read from a file descriptor, so the key never
appears on a command line, where other users and tools on the machine could
read it (it needs bash or zsh). Print `$BENCH_API` once before the first call,
so the user sees where the key goes. Never print `$VERIS_API_KEY`, the
endpoint's secret or `BENCH_TRACE_KEY`. A call that fails returns
`{"detail": ...}` instead of the object you asked for, so every call below
prints `detail` next to the `id`.

## The endpoint

Send the endpoint's own secret the same way, from your environment:

```bash
curl -s -X POST "https://agent.example.com/v3/chat" -H "Content-Type: application/json" \
  -H @<(printf 'Authorization: Bearer %s\n' "$FENWICK_ORDERS_TOKEN") \
  -d '{"message": "What is the status of order 1234?", "session_id": "check-1"}'
curl -s -o /dev/null -w '%{http_code}\n' -X POST "https://agent.example.com/v3/chat" \
  -H "Content-Type: application/json" -d '{"message": "hello"}'
```

The second must not answer `200`.

## Access

```bash
bench "$BENCH_API/benches/$BENCH_ID" | jq '{name, access, detail}'
```

`"access": "write"` is required. With `"read"`: the user is a viewer (they need
the member role), or the bench is a template (fork it: `POST /benches` with
`{"name": "...", "source": {"type": "fork", "bench_id": "<template id>"}}`), or
it is another workspace's bench shared for viewing (ask Veris for a copy).

## World

```bash
bench "$BENCH_API/benches/$BENCH_ID/worlds" \
  | jq '.items[] | {name, scope, services: [.services[].service]}'
```

No items: the bench has no world, and its tasks are conversations only. With a
world, read the tasks (below): a task that expects the agent to change data
in those services needs a twin sandbox, or the agent changes real data instead.

### Twin sandbox

A hosted agent can't reach the twins Veris starts for each attempt. Veris can
set up one long-lived sandbox of the bench's world instead: write to
hello@veris.ai. You get its id and the address of each twin. Point the service
settings of the bench's own deployment at those addresses, never the production
deployment's, and put the id on the candidate as `twin_sandbox_id`. Every attempt shares that sandbox, so a trial
with this candidate runs `parallel: 1`, and a task that names its own world is
refused for it.

## Tasks

```bash
EXAM_ID=$(bench "$BENCH_API/benches/$BENCH_ID/exams" | jq -r '.items[0].id')
bench "$BENCH_API/benches/$BENCH_ID/tasks?exam_id=$EXAM_ID&limit=200" \
  | jq -r '.items[] | "\(.id)  \(.name)  context=\(.agent_context // {} | keys)"'
```

`context` lists the per-task values a task hands the agent (below, "Per-task
values"). Read a task's text with `GET $BENCH_API/tasks/<task id>`.

## Secrets

The endpoint's auth secret goes in the bench's candidate-env, and the channel
refers to it by name. List what the bench holds (values never come back):

```bash
bench "$BENCH_API/benches/$BENCH_ID/candidate-env" | jq -r '.items[] | "\(.key)  secret=\(.is_secret)"'
```

Ask the user to add a missing one in the console: the bench, **Candidates**,
**Add variable**, with **Secret** on. If the user started you with the value in
your environment, you can add it yourself:

```bash
jq -n '{value: $ENV.FENWICK_ORDERS_TOKEN, is_secret: true}' \
  | bench -X PUT "$BENCH_API/benches/$BENCH_ID/candidate-env/FENWICK_ORDERS_TOKEN" \
      -H "Content-Type: application/json" -d @- | jq '{key, is_secret, detail}'
```

Every candidate on the bench shares the bench's candidate-env, so name the
secret after the agent (`FENWICK_ORDERS_TOKEN`). If the name you want already
exists, another candidate may use it: pick another name, and overwrite it only
when the user says it is this agent's and its value changed. Names that start
with `VERIS_` are refused. `BENCH_TRACE_KEY` does not go here: it belongs to the
agent's deployment, not the bench.

## Register

Write `bench/hosted-candidate.json` in the repository:

```json
{
  "name": "fenwick-orders 2026-10-25",
  "harness": null,
  "image": null,
  "channel_config": {
    "init": null,
    "channel": {
      "type": "http",
      "url": "https://agent.example.com/v3/chat",
      "method": "POST",
      "headers": {"Authorization": "Bearer ${env:FENWICK_ORDERS_TOKEN}"},
      "request": {"message_field": "message", "session_field": "session_id"},
      "response": {"type": "json", "message_field": "response", "session_field": "session_id"}
    }
  }
}
```

```bash
bench -X POST "$BENCH_API/benches/$BENCH_ID/candidates" \
  -H "Content-Type: application/json" -d @bench/hosted-candidate.json | jq '{id, name, detail}'
```

- `harness` and `image` are `null`: that makes it a hosted candidate.
- `${env:NAME}` is filled from the bench's candidate-env inside the attempt. A
  raw token in `headers` or the URL is refused when a trial is created.
- A 422 names the field it refused.

### Field mapping

| Field | Default | Meaning |
| --- | --- | --- |
| `type` | — | `http`, `ws` (one text frame in, one frame out per turn) or `voice_ws`. |
| `url` | — | Absolute `https://` (or `wss://`) URL. Private and cloud-metadata addresses are refused. `{session_id}` in the URL is replaced per conversation. |
| `method` | `POST` | HTTP method. |
| `headers` | none | Request headers. Secrets as `${env:NAME}`. |
| `request.message_field` | `message` | Key that carries the user's text. |
| `request.session_field` | `session_id` | Key for the session id; `null` leaves it out. |
| `request.static_fields` | none | Fixed keys added to every request. |
| `request.history` | none | Sends the whole conversation each turn: `{"field", "role_field", "content_field", "user_role", "agent_role"}`. Use it for a stateless endpoint. |
| `response.type` | `json` | `json`, or `sse` for a streamed reply. |
| `response.message_field` | `response` | Key that holds the reply text (`json`). |
| `response.session_field` | `session_id` | Key that holds the session id to send back; `null` if none. |
| `response.chunk_event`, `chunk_field`, `done_event` | — | For `sse`: the event that carries text, the field in its data, and the event that ends the reply. |
| `nudge_after` | none | Seconds of silence before the simulated user speaks again. Raise it for long tool calls. |

A streamed endpoint, as an example:

```json
"response": {"type": "sse", "message_field": "response", "session_field": null,
             "chunk_event": "text", "chunk_field": "delta", "done_event": "done"}
```

### Per-task values

The URL, `headers`, `request.static_fields` and `init` can hold
`${context:KEY}`, filled from each task's `agent_context`. Use it only when the
tasks set those keys: a key a task doesn't set fails the trial at creation, and
so does a task that sets `agent_context` when the channel uses none of it.

### A new version

Each version is a new candidate with its own URL, so trials compare versions.
To fix the current version's channel instead, send the whole `channel_config`:

```bash
jq '{channel_config}' bench/hosted-candidate.json \
  | bench -X PATCH "$BENCH_API/candidates/cand_..." \
      -H "Content-Type: application/json" -d @- | jq '{id, detail}'
```

## Connection check

```bash
bench -X POST "$BENCH_API/benches/$BENCH_ID/candidates/cand_.../connection-check" \
  -H "Content-Type: application/json" -d '{}' | jq '{ok, stage, latency_ms, detail}'
```

With per-task values, send sample ones: `-d '{"context": {"trial_id": "..."}}'`.
The check sends one real message to the endpoint and waits up to 10 seconds for
its reply or first streamed event. `detail` names a reason, a status or an error
class, never a header or a body.

| `stage` | Fails when | Fix |
| --- | --- | --- |
| `resolve` | A `${env:…}` or `${context:…}` value is missing. | Add the candidate-env secret, or send the context value. |
| `connect` | The URL doesn't resolve, refuses the connection, or is private (`blocked_destination`). | A public URL the internet can reach. |
| `setup`, `init`, `first_frame` | The channel's setup call, init step or first WebSocket frame failed. | The named step, against the endpoint's contract. |
| `probe` | The http reply failed: a status (`HTTP 401`), `ReadTimeout`, not JSON, or no `message_field`. | `401`/`403`: the auth header or secret. `ReadTimeout`: send one request to wake it, then check again. The rest: the field mapping. |
| `unsupported` | The channel type can't be checked. | Go on to the smoke trial. |

## Smoke trial

```bash
bench -X POST "$BENCH_API/benches/$BENCH_ID/trials" -H "Content-Type: application/json" \
  -d '{"name": "smoke", "kind": "smoke", "candidate_ids": ["cand_..."],
       "task_ids": ["task_...", "task_..."], "persona_ids": [], "repeats": 1}' \
  | jq '{id, status, detail}'
```

With a twin sandbox, add `"parallel": 1`. Check progress about once a minute,
until `pending` is 0:

```bash
bench "$BENCH_API/trials/trial_.../results" \
  | jq '.detail // (.rollups[] | select(.candidate_id == "cand_...") | {pending, n, passes})'
```

## Verify

```bash
TRIAL_ID=trial_...; CANDIDATE_ID=cand_...
bench "$BENCH_API/trials/$TRIAL_ID/attempts?candidate_id=$CANDIDATE_ID&limit=50" \
  | jq -r '.items[].id' | while read -r a; do
    att=$(bench "$BENCH_API/attempts/$a")
    llm=$(bench "$BENCH_API/attempts/$a/artifacts/agent_trace.json" | jq '.llm_calls // 0' 2>/dev/null)
    jq -c --argjson llm "${llm:-0}" \
      '{id, status, turns, llm_calls: $llm, tool_calls, agent_trace_reason, passed, error_end: (.error // "" | .[-300:])}' <<<"$att"
  done
```

Read each attempt's conversation and what the grader saw:

```bash
bench "$BENCH_API/attempts/att_.../artifacts/transcript.jsonl" | jq -r '"[\(.speaker)] \(.content)"'
bench "$BENCH_API/attempts/att_.../artifacts/agent_trace.json" \
  | jq '{llm_calls, tool_calls, turns: [.turns[] | {role, content: (.content // "" | .[:120]), calls: [.tool_calls[]?.name]}]}'
```

A tool result is its own turn after the call, carrying the call's
`tool_call_id`: role `tool`, or role `user` for Anthropic-style traces.

```bash
bench "$BENCH_API/attempts/att_.../artifacts/agent_trace.json" \
  | jq -r '.turns[] | select(.tool_call_id) | "\(.tool_call_id): \(.content[:200])"'
```

`agent_trace_reason` for a hosted http candidate: `null` when its spans arrived,
`hosted_candidate` when none did, `trace_fetch_failed` when they couldn't be
read. To see why a task did not pass, read `assertion_results` on the attempt.

## Re-run

After a fix (a redeploy, or a PATCH above), re-run the candidate in the same
trial once nothing of it is pending:

```bash
bench -X POST "$BENCH_API/trials/trial_.../candidates" -H "Content-Type: application/json" \
  -d '{"candidate_ids": ["cand_..."], "replace": true}' | jq '{id, status, detail}'
```
