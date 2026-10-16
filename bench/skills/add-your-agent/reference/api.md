# Bench API calls

Every call sends the key as a bearer token. Set these once per shell:

```bash
BENCH_API=${BENCH_API:-https://bench.api.veris.ai/v1}
AUTH="Authorization: Bearer $VERIS_API_KEY"
BENCH_ID=bench_...
```

Never print `$VERIS_API_KEY` or a secret's value, and never write one to a
file. Pass a secret into a request body with `jq --arg`, as in "Secrets".
A call that fails returns `{"detail": ...}` instead of the object you asked
for, so check for `.detail` before you use the result. `{"detail": "not
signed in"}` means the key is missing or malformed, for example with quotes or
a trailing carriage return left on it.

## Access

```bash
curl -s "$BENCH_API/benches/$BENCH_ID" -H "$AUTH" | jq '{name, access}'
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

```bash
curl -s "$BENCH_API/benches/$BENCH_ID/tasks?limit=200" -H "$AUTH" \
  | jq -r '.items[] | "\(.id)  \(.name)"'
```

For a smoke trial, pick two tasks that need the agent's tools, such as ones
that change data, so the twin check means something. Read a task's text with
`GET $BENCH_API/tasks/<task id>` when the name doesn't say.

## Push and pin

```bash
IMAGE=<registry>/<name>
docker buildx build --platform linux/amd64 -t "$IMAGE:<version>" --push .
DIGEST=$(docker buildx imagetools inspect "$IMAGE:<version>" --format '{{json .Manifest}}' | jq -r .digest)
REF="$IMAGE@$DIGEST"
```

Register `$REF`, the digest form. A bare name or `:latest` is refused, and a
tag that moves would change the candidate under its trials.

A push that hangs with no output is usually the registry's credential helper
waiting for a login. Ask the user to sign in to the registry (for example
`docker login ghcr.io`, or `gcloud auth login` for Google Artifact Registry),
then retry.

```bash
curl -s -X POST "$BENCH_API/registries/check-image" -H "$AUTH" \
  -H "Content-Type: application/json" -d "$(jq -n --arg r "$REF" '{ref: $r}')"
```

| `status` | Meaning | Next |
| --- | --- | --- |
| `public` | Pulls without a login. | Register. |
| `ok` | Pulls with a login the workspace saved. | Register. |
| `needs_login` | The registry wants a login; the workspace has none. | Save one, below. |
| `denied` | The saved login was refused, or can't read this repository. | Ask the user for a working read-only token. |
| `not_found` | No such tag or digest. | Check `$REF`. |

Save a registry login once per workspace. Ask the user for a read-only token
(for GitHub, a classic token with only `read:packages`); have them export it
rather than paste it into the chat.

```bash
jq -n --arg s "$REGISTRY_TOKEN" \
  '{kind: "github", prefix: "ghcr.io/<org>", username: "<user>", secret: $s}' \
  | curl -s -X PUT "$BENCH_API/registries" -H "$AUTH" -H "Content-Type: application/json" -d @-
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

Add a missing one from an environment variable the user exported:

```bash
jq -n --arg v "$OPENAI_API_KEY" '{value: $v, is_secret: true}' \
  | curl -s -X PUT "$BENCH_API/benches/$BENCH_ID/candidate-env/OPENAI_API_KEY" \
      -H "$AUTH" -H "Content-Type: application/json" -d @-
```

Every candidate on the bench gets the bench's candidate-env. Plain
per-candidate settings, such as `MODEL`, go in `image.env` instead; anyone who
can read the bench can read it. Names that start with `VERIS_` are refused in
both.

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
CANDIDATE_ID=$(jq --arg r "$REF" '.image.ref = $r' bench/candidate.json \
  | curl -s -X POST "$BENCH_API/benches/$BENCH_ID/candidates" \
      -H "$AUTH" -H "Content-Type: application/json" -d @- | jq -r .id)
```

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
TRIAL_ID=$(jq -n --arg c "$CANDIDATE_ID" --arg a "<task id>" --arg b "<task id>" \
  '{name: "smoke", kind: "smoke", candidate_ids: [$c], task_ids: [$a, $b], persona_ids: [], repeats: 1}' \
  | curl -s -X POST "$BENCH_API/benches/$BENCH_ID/trials" \
      -H "$AUTH" -H "Content-Type: application/json" -d @- | jq -r .id)
```

Wait until nothing is pending. Keep polling: the bench moves a trial forward
when someone reads it. Right after creation the candidate may have no rollup
yet, which prints nothing.

```bash
while :; do
  left=$(curl -s "$BENCH_API/trials/$TRIAL_ID/results" -H "$AUTH" \
    | jq --arg c "$CANDIDATE_ID" '.rollups[] | select(.candidate_id == $c) | .pending')
  echo "$(date +%T) pending: ${left:-not started}"
  [ "$left" = 0 ] && break
  sleep 30
done
```

A smoke trial usually takes a few minutes. Stop after 30 and read the
attempts anyway.

## Verify

```bash
curl -s "$BENCH_API/trials/$TRIAL_ID/attempts?candidate_id=$CANDIDATE_ID&limit=50" -H "$AUTH" \
  | jq '.items[] | {id, status, turns, input_tokens, tool_calls, agent_trace_reason,
        twins: ([.ledger_summary.sources[]? | select(.kind == "service") | {(.name): .events}] | add),
        passed, error: (.error // "" | .[0:500])}'
```

Check each attempt against the table in `SKILL.md`. To see why a task did not
pass, read `assertion_results` on the attempt: each entry has a `statement`,
`passed` and the judge's `reasoning`.

### Artifacts

```bash
curl -s "$BENCH_API/attempts/$ATTEMPT_ID" -H "$AUTH" | jq '.artifact_uris | keys'
curl -s "$BENCH_API/attempts/$ATTEMPT_ID/artifacts/candidate.log" -H "$AUTH" | tail -50
```

| Artifact | What it shows |
| --- | --- |
| `candidate.log` | The container's stdout and stderr. |
| `transcript.jsonl` | The conversation, one turn per line. |
| `agent_trace.json` | The model calls the grader read. Tool results: `jq '.turns[] \| select(.role == "tool") \| .content'`. |
| `ledger.jsonl` | Every request the twins received. |

The console shows the same: `https://benchmark.veris.ai/benches/<bench id>?trial=<trial id>`.

## Fix and re-run

After a fix, push a new digest, point the candidate at it, and re-run the
candidate in the same trial. `image` is replaced as a whole, so send all of
it:

```bash
jq --arg r "$NEW_REF" '{image: (.image + {ref: $r})}' bench/candidate.json \
  | curl -s -X PATCH "$BENCH_API/candidates/$CANDIDATE_ID" \
      -H "$AUTH" -H "Content-Type: application/json" -d @-

jq -n --arg c "$CANDIDATE_ID" '{candidate_ids: [$c], replace: true}' \
  | curl -s -X POST "$BENCH_API/trials/$TRIAL_ID/candidates" \
      -H "$AUTH" -H "Content-Type: application/json" -d @-
```

The re-run is refused while any of the candidate's attempts is still pending
(`... still in flight; re-run once they settle`); wait first. Update
`bench/candidate.json` with the new `ref`. Then wait and verify again. Once the smoke trial is clean, every later version
of the agent is a new candidate with its own digest, so trials can compare
versions.
