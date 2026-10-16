# What goes in the image

## The server contract

The bench's simulated user talks to the container one turn at a time.

**http** (the default). Each user turn is one request:

```text
POST /chat
{"message": "Hi, my card was stolen.", "session_id": "a1b2c3"}

200
{"response": "I'm sorry to hear that. Which card is it?", "session_id": "a1b2c3"}
```

The first request has no `session_id`. Return one, and every later request in
that conversation carries it back. You choose the path and field names; the
candidate's `channel_config` maps them (`reference/api.md`, "Field mapping").

**ws.** One text frame in is one user turn. Send the reply as one text frame,
or stream it without a pause longer than about one second: a longer pause ends
the reply. Keep history per connection; the bench opens one per attempt.

Either way the server must:

- listen on `0.0.0.0` and a port of 1024 or above, as a user other than root;
- answer within 600 seconds of the container starting, and serve a health path
  that returns 2xx once it can answer;
- log to stdout and stderr: a failed attempt shows the last lines, and every
  attempt keeps them as `candidate.log`.

If the agent presents choices, put them on one line of the reply as
`Options: a | b | c`. Write links as `text (https://...)`.

## The server file

Wrap the agent's own turn function. Don't reimplement the agent.

Python (`bench_server.py`, FastAPI):

```python
"""The Veris Bench entry point: an http server around the agent."""

import json
import logging
import os
import uuid

# Point the agent at the bench's twins before its modules read their settings.
twins = json.loads(os.environ.get("VERIS_DS_SERVICE_URLS", "{}"))
if "postgres" in twins:
    os.environ["BANK_DB_URL"] = twins["postgres"]  # the variable the agent reads

from fastapi import FastAPI  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from app.agent import new_conversation, run_turn  # noqa: E402  the agent's own

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("bench_server")
log.info("twins: %s", sorted(twins))

app = FastAPI()
conversations: dict[str, object] = {}


class Turn(BaseModel):
    message: str
    session_id: str | None = None


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/chat")
async def chat(turn: Turn) -> dict:
    session_id = turn.session_id or uuid.uuid4().hex
    conversation = conversations.setdefault(session_id, new_conversation())
    reply = await run_turn(conversation, turn.message)
    return {"response": reply, "session_id": session_id}
```

Node (`bench_server.mjs`, no extra dependency):

```js
// The Veris Bench entry point: an http server around the agent.
import http from "node:http";
import { randomUUID } from "node:crypto";

// Point the agent at the bench's twins before its modules read their settings.
const twins = JSON.parse(process.env.VERIS_DS_SERVICE_URLS ?? "{}");
if (twins.postgres) {
  const dsn = new URL(twins.postgres);
  dsn.searchParams.set("uselibpqcompat", "true"); // see "Twins"
  process.env.PG_CONNECTION = dsn.toString(); // the variable the agent reads
}
console.log("twins:", Object.keys(twins).sort().join(", "));

const { newConversation, reply } = await import("./src/agent.js"); // the agent's own

const conversations = new Map();

async function readJson(req) {
  let body = "";
  for await (const chunk of req) body += chunk;
  return JSON.parse(body);
}

function send(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(payload));
}

http
  .createServer(async (req, res) => {
    if (req.method === "GET" && req.url === "/health") return send(res, 200, { status: "ok" });
    if (req.method !== "POST" || req.url !== "/chat") return send(res, 404, { error: "not found" });
    try {
      const { message, session_id } = await readJson(req);
      const sessionId = session_id ?? randomUUID();
      if (!conversations.has(sessionId)) conversations.set(sessionId, newConversation());
      const text = await reply(conversations.get(sessionId), message);
      send(res, 200, { response: text, session_id: sessionId });
    } catch (err) {
      console.error(err);
      send(res, 500, { error: String(err) });
    }
  })
  .listen(8008, "0.0.0.0", () => console.log("listening on 8008"));
```

Adapt the names: the turn function, how a conversation is created, and the
variable each twin's address goes into. Load the agent's modules after the
twin mapping (Python: import below it; Node: `await import`), so settings read
at import time see the twin.

## Twins

Each task runs in a fresh world of twins: working copies of the services the
agent calls. The container gets their addresses as environment variables:

- `VERIS_DS_SERVICE_URLS`: JSON, `{"<service name>": "<address>"}` for every
  twin. Service names are the ones the bench's world lists. For a database the
  address is a DSN; for an http service it is a base URL.
- One variable per twin with the same address, named for what the vendor's
  clients usually read (`DATABASE_URL` for Postgres, `STRIPE_API_BASE` for
  Stripe). If the agent already reads that variable, it needs no mapping.

The container has no DNS interception: an address written into the code, such
as `https://api.stripe.com` or `localhost:5432`, reaches the real host, not
the twin.

Client fixes:

- **node-postgres (`pg`) 8.16+**: the twin DSN carries `sslmode=require`,
  which `pg` treats as `verify-full`, and the twin's certificate is
  self-signed, so every query fails. Set `uselibpqcompat=true` in the DSN's
  query, as the Node example does, or pass `ssl: { rejectUnauthorized: false }`.
  psycopg connects as it is.
- **An http SDK**: set its base URL from the twin's address (for example the
  SDK's `base_url` or `api_base` option).

## Telemetry

Veris records the agent's model calls, tool calls and tool results from inside
the process, so the grader can read them beside the transcript. Nothing in the
image turns this on. It works when:

- the agent is a Python process, or Node 18.19+ or 20.6+ (`node` or `npm
  start`; not Bun or Deno);
- it calls its model through a supported SDK. Python: OpenAI, OpenAI Agents,
  Anthropic, Mistral, Google GenAI, LangChain. Node: OpenAI (the `openai`
  package 5 or later; 4.x records nothing), Anthropic, Claude Agent SDK,
  LangChain, AWS Bedrock, and the Vercel AI SDK with
  `experimental_telemetry: { isEnabled: true }`;
- its tools are model function tools;
- you set no `OTEL_*` variable and install no OpenTelemetry provider of your
  own;
- any `PYTHONPATH` or `NODE_OPTIONS` you need is in the candidate's
  `image.env`, not only in the Dockerfile (the platform sets both);
- Node only: the working directory is the package directory (where
  `node_modules` is), and the run user can write to it. The hook copies its
  packages there; when it can't, it does nothing and says nothing.

How to tell it worked, on a bench attempt: `agent_trace_reason` is `null` and
`input_tokens` is above 0. A Node agent's `candidate.log` also has a line
`veris-otel-node: instrumented <SDK>` for each SDK the hook patched.

## Dockerfile

Python with uv:

```dockerfile
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:0.9 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project
COPY . .
RUN useradd --uid 10001 agent && chown -R agent /app
USER agent
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8008
CMD ["uvicorn", "bench_server:app", "--host", "0.0.0.0", "--port", "8008"]
```

Node:

```dockerfile
FROM node:22-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
RUN chown -R node:node /app
USER node
EXPOSE 8008
CMD ["node", "bench_server.mjs"]
```

- Add the server's own dependencies (FastAPI and uvicorn for Python) to the
  project's dependency file, so the lockfile stays the source of truth.
- `WORKDIR` is where the agent expects to run: files it opens by a relative
  path must be there.
- Never `COPY` a `.env` or key file, and never set a secret with `ENV`. The
  `.dockerignore` excludes `.env`, `.git`, `node_modules` and local virtual
  environments.

## Local check

```bash
docker build --platform linux/amd64 -t bench-local .
docker run --rm -d --name bench-local -p 8008:8008 \
  -e OPENAI_API_KEY="${OPENAI_API_KEY:-sk-placeholder}" bench-local
curl -s localhost:8008/health
curl -s -X POST localhost:8008/chat -H 'Content-Type: application/json' \
  -d '{"message": "Hello"}'
docker logs bench-local
docker rm -f bench-local
```

On Apple Silicon the image runs under emulation; that is expected. Without a
model key on the machine, the placeholder lets the model client start, and the
turn then fails at the model call with an authentication error or a timeout,
in the response or the log. That still proves the turn reached the agent.
Without twin variables the agent uses its own defaults, so a tool failure here
can be normal; on the bench it is not.
