# Bench API calls

Most coding agents run each command in a new shell, so a variable you set in
one command is gone in the next. Start every command with these lines, and
write ids into later commands as literal text after you print them:

```bash
BENCH_API=${BENCH_API:-https://bench.api.veris.ai/v1}
AUTH="Authorization: Bearer $VERIS_API_KEY"
BENCH_ID=bench_...
```

Never print `$VERIS_API_KEY` or a secret's value, and never write one to a
file or put one on a command line. A call that fails returns `{"detail": ...}`
instead of the object you asked for, so every call below prints `detail` next
to the `id`. `{"detail": "not signed in"}` means the key is missing or
malformed, for example with quotes or a trailing carriage return left on it.

## Access

```bash
curl -s "$BENCH_API/benches/$BENCH_ID" -H "$AUTH" | jq '{name, access, detail}'
```

`"access": "write"` is required. `"read"` has three causes:

- the user is a viewer in their workspace: they need the member role;
- the bench is a template: fork it (`POST /benches` with
  `{"name": "...", "source": {"type": "fork", "bench_id": "<template id>"}}`)
  and use the fork;
- the bench belongs to another workspace and is shared for viewing: it can't
  be forked; the user asks Veris for a copy.

## World

```bash
curl -s "$BENCH_API/benches/$BENCH_ID/worlds" -H "$AUTH" \
  | jq '.items[] | {name, scope, services: [.services[].service]}'
```

The bench's own world has `"scope": "bench"`. A task can name its own world
(`"scope": "task"`); include those services too.

## Tasks

A trial runs tasks from the bench's exam, so list the exam's tasks:

```bash
EXAM_ID=$(curl -s "$BENCH_API/benches/$BENCH_ID/exams" -H "$AUTH" | jq -r '.items[0].id')
curl -s "$BENCH_API/benches/$BENCH_ID/tasks?exam_id=$EXAM_ID&limit=200" -H "$AUTH" \
  | jq -r '.items[] | "\(.id)  \(.name)"'
```

For a smoke trial, pick two tasks that need the agent's tools, such as ones
that change data, so the twin check means something. Read a task's text with
`GET $BENCH_API/tasks/<task id>` when the name doesn't say.

## Push and pin

```bash
IMAGE=<registry>/<name>
docker buildx build --platform linux/amd64 -t "$IMAGE:<version>" --push .
echo "$IMAGE@$(docker buildx imagetools inspect "$IMAGE:<version>" --format '{{json .Manifest}}' | jq -r .digest)"
```

The printed `<image>@sha256:...` is the reference to register. A bare name or
`:latest` is refused, and a tag that moves would change the candidate under
its trials. A push that hangs with no output is usually the registry's
credential helper waiting for a login: ask the user to sign in to the registry
(for example `docker login ghcr.io`, or `gcloud auth login` for Google Artifact
Registry), then retry.

```bash
curl -s -X POST "$BENCH_API/registries/check-image" -H "$AUTH" \
  -H "Content-Type: application/json" -d '{"ref": "<image>@sha256:..."}' | jq '{status, detail}'
```

| `status` | Meaning | Next |
| --- | --- | --- |
| `public` | Pulls without a login. | Register. |
| `ok` | Pulls with a login the workspace saved. | Register. |
| `needs_login` | The registry wants a login; the workspace has none. | Save one, below. |
| `denied` | The saved login was refused, or can't read this repository. | The user replaces the login with a working read-only token. |
| `not_found` | No such tag or digest. | Check the reference. |
| `unreachable`, `invalid`, `error` | The registry didn't answer, the reference is malformed, or the check failed. | Read `detail`. |

**Registry login.** Saved once per workspace. The simplest path is for the user
to add it in the console: **Overview**, **Registries**, **Connect** (or
**Manage**), **Add registry**. If the user started you with a read-only token in
`REGISTRY_TOKEN` (for GitHub, a classic token with only `read:packages`), you
can save it yourself:

```bash
jq -n '{kind: "github", prefix: "ghcr.io/<org>", username: "<user>", secret: $ENV.REGISTRY_TOKEN}' \
  | curl -s -X PUT "$BENCH_API/registries" -H "$AUTH" -H "Content-Type: application/json" -d @- \
  | jq '{id, prefix, detail}'
```

`kind` is one of `dockerhub`, `github`, `gitlab`, `azure`, `ecr`, `gar`,
`other`. For `ecr`, `username` is the access key id and `region` is required.
For `gar`, `secret` is the service account key JSON. Then run `check-image`
again: it should say `ok`. Prefer GitHub Container Registry or Google Artifact
Registry; Docker Hub's anonymous pull limit fails attempts.

## Secrets

List what the bench already holds (values never come back):

```bash
curl -s "$BENCH_API/benches/$BENCH_ID/candidate-env" -H "$AUTH" | jq -r '.items[] | "\(.key)  secret=\(.is_secret)"'
```

For each secret the agent needs and the bench lacks, ask the user to add it in
the console: the bench, **Candidates**, **Add variable**, with **Secret** on. If
the user started you with the value in your environment, you can add it
yourself:

```bash
jq -n '{value: $ENV.OPENAI_API_KEY, is_secret: true}' \
  | curl -s -X PUT "$BENCH_API/benches/$BENCH_ID/candidate-env/OPENAI_API_KEY" \
      -H "$AUTH" -H "Content-Type: application/json" -d @- | jq '{key, is_secret, detail}'
```

Every candidate on the bench gets the bench's candidate-env. Plain
per-candidate settings go in `image.env` instead; anyone who can read the bench
can read it. Names that start with `VERIS_` are refused in both. The
candidate-env also refuses names that Veris's own agents use, such as `MODEL`
and `SYSTEM_PROMPT`; put those in `image.env`.

## Register

Write `bench/candidate.json` in the repository. It holds no secrets, so it can
be committed, and CI can reuse it with a new `ref`.

```json
{
  "name": "my-agent 1.0",
  "image": {
    "ref": "<registry>/<name>@sha256:...",
    "port": 8008,
    "path": "/chat",
    "health_path": "/health",
    "working_dir": "/app",
    "env": {"MODEL": "gpt-4.1-mini"}
  },
  "channel_config": {
    "init": null,
    "channel": {
      "type": "http",
      "url": null,
      "method": "POST",
      "request": {"message_field": "message", "session_field": "session_id"},
      "response": {"type": "json", "message_field": "response", "session_field": "session_id"}
    }
  }
}
```

```bash
curl -s -X POST "$BENCH_API/benches/$BENCH_ID/candidates" \
  -H "$AUTH" -H "Content-Type: application/json" -d @bench/candidate.json | jq '{id, name, detail}'
```

- `working_dir` is the Dockerfile's `WORKDIR`. Without it, on a world that
  holds files, the container starts in `/workspace` and the server's relative
  paths break.
- `channel.url` stays `null`: the bench builds it from `image.port` and
  `image.path`.
- For a ws server: `"channel": {"type": "ws", "url": null}`, and `image.path`
  is the WebSocket path (`/` by default).
- A 422 names the field it refused. `image ref ':latest' is not a pin` and
  `image ref must carry a tag or an @sha256 digest` mean: use the digest.

### Field mapping

Set these on `channel_config.channel` when the server doesn't use the default
shape.

| Field | Default | Meaning |
| --- | --- | --- |
| `method` | `POST` | HTTP method. |
| `headers` | none | Extra request headers. |
| `request.message_field` | `message` | Key that carries the user's text. |
| `request.session_field` | `session_id` | Key for the session id; `null` leaves it out. |
| `request.static_fields` | none | Fixed keys added to every request. |
| `request.history` | none | Sends the whole conversation in each request. |
| `response.type` | `json` | `json`, or `sse` for a streamed reply. |
| `response.message_field` | `response` | Key that holds the reply text. |
| `response.session_field` | `session_id` | Key that holds the session id to send back. |
| `nudge_after` | none | Seconds of silence before the simulated user speaks again. Raise it for long tool calls. |

## Smoke trial

```bash
curl -s -X POST "$BENCH_API/benches/$BENCH_ID/trials" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"name": "smoke", "kind": "smoke", "candidate_ids": ["cand_..."],
       "task_ids": ["task_...", "task_..."], "persona_ids": [], "repeats": 1}' \
  | jq '{id, status, detail}'
```

Check progress about once a minute, until `pending` is 0. Keep checking: the
bench moves a trial forward when someone reads it. Right after creation the
candidate may have no row yet.

```bash
curl -s "$BENCH_API/trials/trial_.../results" -H "$AUTH" \
  | jq '.detail // (.rollups[] | select(.candidate_id == "cand_...") | {pending, n, passes})'
```

A smoke trial usually takes a few minutes. After 30, verify what has finished
and tell the user what is still pending.

## Verify

For each attempt, this prints the checks in `SKILL.md`: the attempt's fields,
the model calls in its trace, and whether the agent sent requests to each twin.

```bash
TRIAL_ID=trial_...; CANDIDATE_ID=cand_...
curl -s "$BENCH_API/trials/$TRIAL_ID/attempts?candidate_id=$CANDIDATE_ID&limit=50" -H "$AUTH" \
  | jq -r '.items[].id' | while read -r a; do
    att=$(curl -s "$BENCH_API/attempts/$a" -H "$AUTH")
    llm=$(curl -s "$BENCH_API/attempts/$a/artifacts/agent_trace.json" -H "$AUTH" | jq '.llm_calls // 0' 2>/dev/null)
    twins=""
    for s in $(jq -r '.ledger_summary.sources[]? | select(.kind == "service") | .name' <<<"$att"); do
      n=$(curl -s "$BENCH_API/attempts/$a/ledger?plane=vendor&source=$s&limit=1" -H "$AUTH" | jq '.events | length')
      twins="$twins$s:$n "
    done
    jq -c --argjson llm "${llm:-0}" --arg twins "$twins" \
      '{id, status, turns, llm_calls: $llm, tool_calls, agent_trace_reason, reached: $twins,
        passed, error_end: (.error // "" | .[-300:])}' <<<"$att"
  done
```

`reached` shows `1` for each twin that received at least one request from the
agent, `0` otherwise. To see why a task did not pass, read `assertion_results`
on the attempt: each entry has a `statement`, `passed` and the grader's
`reasoning`.

### Artifacts

```bash
curl -s "$BENCH_API/attempts/att_..." -H "$AUTH" | jq '.artifact_uris | keys'
curl -s "$BENCH_API/attempts/att_.../artifacts/candidate.log" -H "$AUTH" | tail -50
```

| Artifact | What it shows |
| --- | --- |
| `candidate.log` | The container's stdout and stderr. |
| `transcript.jsonl` | The conversation, one turn per line. |
| `agent_trace.json` | The model calls the grader read. Tool results: `jq '.turns[] \| select(.role == "tool") \| .content'`. |
| `ledger.jsonl` | Every request the twins received. |

The console shows the same: `https://benchmark.veris.ai/benchmarks/<bench id>?trial=<trial id>`.

## Fix and re-run

After a fix, push a new digest, put it in `bench/candidate.json`, point the
candidate at it, and re-run the candidate in the same trial. `image` is
replaced as a whole, so send all of it:

```bash
jq '{image}' bench/candidate.json \
  | curl -s -X PATCH "$BENCH_API/candidates/cand_..." \
      -H "$AUTH" -H "Content-Type: application/json" -d @- | jq '{id, image: .image.ref, detail}'

curl -s -X POST "$BENCH_API/trials/trial_.../candidates" -H "$AUTH" -H "Content-Type: application/json" \
  -d '{"candidate_ids": ["cand_..."], "replace": true}' | jq '{id, status, detail}'
```

The re-run is refused while any of the candidate's attempts is still pending
(`... still in flight; re-run once they settle`); wait first. Then check
progress and verify again. Once the smoke trial is clean, every later version
of the agent is a new candidate with its own digest, so trials can compare
versions.
