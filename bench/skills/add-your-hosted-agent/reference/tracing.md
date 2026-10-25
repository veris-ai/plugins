# Let the grader see a hosted agent's model calls

For a hosted http endpoint, each turn's request carries an `X-Veris-Traceparent`
header (and a `traceparent` header with the same value). If the agent's
model-call spans belong to that trace and reach Veris within 10 seconds of the
conversation's end, the grader reads them beside the transcript: the tool calls,
their results, the system prompt, token counts.

`bench_tracing.py` and `bench_tracing.mjs` do this, and only this. Copy the one
for the agent's language into the agent, next to its entry point, unchanged.

## What the module sends, and what it never sends

These guarantees are why the module exists instead of a few lines of
OpenTelemetry setup. Don't weaken them when you wire it in:

- **Off unless `BENCH_TRACE_KEY` is set.**
- **Only requests the endpoint authenticated as the bench.** The route passes
  `from_bench` (Node: `fromBench`) from its own auth result. Without it, or
  without the header, nothing is recorded.
- **Only while the turn runs, inside the turn.** A span is sent only if it
  started while that bench turn was running, in the turn's own context. Work
  that outlives the turn (a background worker, a timer, a queue consumer) and
  other requests' work are never sent, even when the agent has its own tracing
  that samples everything, and even when a caller sends a live `traceparent`.
- **Only model calls.** Only OpenInference model-call spans and the turn span
  leave the process. Database, HTTP and other spans don't, exception messages
  and stack traces are stripped, and the process's resource attributes (host,
  cluster, environment) are replaced.
- **Only to Veris, with one key.** The module's own exporter sends exactly
  `Authorization` and `Content-Type`. No `OTEL_*` setting, credential provider or
  redirect can add a header or change the destination, and `BENCH_TRACE_URL` must
  be an `https` veris.ai address (`http` only on this machine, for the local
  check). An export failure is logged without the key and never fails a request.

What it does send: a bench turn's model calls in full, meaning the prompts, the
system prompt, tool calls and tool results. One case remains: work for another
user that runs inside a bench turn's context while the turn is running (a batch
that mixes users' items, a shared worker started by the bench request) is sent
with it. A deployment that serves only the bench rules that out.

## Security rules

- **A deployment of its own for the bench.** Run the bench against its own
  service or instances, with test data and an account that can reach only what
  the bench needs, not the production instance real users reach. If the user
  insists on a shared deployment, tell them plainly what the paragraph above
  says can be sent, and go on only when they agree.
- **A credential only the bench uses.** `from_bench` is only as good as the
  endpoint's ability to tell the bench apart. If every caller shares one token,
  propose a second one for the bench (`BENCH_CALLER_TOKEN`, accepted by the same
  auth check, compared in constant time with `hmac.compare_digest` or Node's
  `crypto.timingSafeEqual`), set `from_bench` from which one matched, and make
  that change only with the user's OK. Generate it without printing it, straight
  into the deployment's secret store and the bench's candidate-env
  (`reference/api.md`, "Secrets", with the variable you generated). Give it the least access the bench needs and rotate it
  after the trials: the bench's candidate-env reaches every image and harness
  candidate on the bench.
- **Keys stay out of sight.** `BENCH_TRACE_KEY` goes in the deployment's secret
  store, fed from your environment through stdin or a file the platform reads
  (`gcloud secrets versions add NAME --data-file=-`, `kubectl create secret
  generic NAME --from-env-file=...`). Never in code, a committed file, a
  Dockerfile, a log line or a command line, and never `VERIS_API_KEY`, which can
  change the user's benches. Never ask the user to paste a key into the chat.
- **Call `bench_turn` only after the endpoint's own auth check.**
- **Secrets in prompts.** If the agent puts a secret into a prompt or a tool
  result (an internal token, a connection string), stop and tell the user: it
  would be sent.
- **`BENCH_TRACE_URL`.** Set it only when the user gives you another Veris
  address.

## Packages

Add them with the project's package manager, so the lockfile records the
versions:

| Language | Packages |
| --- | --- |
| Python | `opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-common`, and the OpenInference instrumentor for the agent's model SDK |
| Node | `@opentelemetry/api`, `@opentelemetry/core`, `@opentelemetry/context-async-hooks`, `@opentelemetry/sdk-trace`, `@opentelemetry/resources`, `@opentelemetry/otlp-transformer`, and the OpenInference instrumentation for the agent's model SDK |

OpenInference instrumentors, by model SDK:

| SDK | Python | Node |
| --- | --- | --- |
| OpenAI (Chat Completions, Responses) | `openinference-instrumentation-openai` | `@arizeai/openinference-instrumentation-openai` |
| OpenAI Agents SDK | `openinference-instrumentation-openai-agents` | — |
| Anthropic | `openinference-instrumentation-anthropic` | `@arizeai/openinference-instrumentation-anthropic` |
| LangChain, LangGraph | `openinference-instrumentation-langchain` | `@arizeai/openinference-instrumentation-langchain` |
| Google GenAI | `openinference-instrumentation-google-genai` | — |
| Mistral | `openinference-instrumentation-mistralai` | — |
| Bedrock | `openinference-instrumentation-bedrock` | `@arizeai/openinference-instrumentation-bedrock` |

Check that the instrumentor supports the agent's installed SDK version: an
instrumentor that can't patch the SDK records nothing and says so only in a
warning at startup. The instrumentor patches every model call the process
makes; the module decides which leave.

**Node: the OpenTelemetry JS 3.x line.** The Node module needs
`@opentelemetry/sdk-trace` 3.x, which pins `@opentelemetry/api` to one minor
release. If npm stops with `ERESOLVE` on `@opentelemetry/api`, the agent already
uses other OpenTelemetry packages: stop and tell the user. Moving the agent's
OpenTelemetry stack is their call. Never use `--force`.

## Wire it in

Three changes, all in the agent's server code.

**1. At startup**, before the model SDK is used:

```python
import bench_tracing
from openinference.instrumentation.openai import OpenAIInstrumentor

if provider := bench_tracing.configure():
    OpenAIInstrumentor().instrument(tracer_provider=provider)
```

```js
import OpenAI from "openai";
import { OpenAIInstrumentation } from "@arizeai/openinference-instrumentation-openai";
import { configure } from "./bench_tracing.mjs";

const provider = configure();
if (provider) {
  const inst = new OpenAIInstrumentation();
  inst.setTracerProvider(provider);
  inst.manuallyInstrument(OpenAI);
}
```

Swap in the instrumentor for the agent's SDK. In Node, pass `manuallyInstrument`
the SDK's module object or default export, as that instrumentation's README
shows. `configure` raises (throws) at startup if `BENCH_TRACE_URL` isn't a Veris
address: fix the setting, don't catch it.

**If the agent already traces its model calls** (it creates a `TracerProvider`
and instruments the SDK with it, for its own observability), don't instrument
twice. Hand the module that provider instead:

- Python: `bench_tracing.configure(existing_provider)`, and keep the agent's
  instrument call as it is.
- Node: add `benchSpanProcessor()` to the provider's `spanProcessors` where it is
  constructed (skip it when it returns `null`), and call
  `configure({ provider })`.

If the existing provider samples less than all traces, bench turns may be
dropped: tell the user.

**2. Around each request's agent work**, right after the auth check:

```python
@app.post("/chat")
async def chat(body: ChatIn, request: Request) -> dict:
    caller = authenticate(request)  # the endpoint's own auth: raises when it fails
    with bench_tracing.bench_turn(request.headers, from_bench=caller == "veris-bench"):
        reply = await run_agent(body.message, body.session_id)
    return {"response": reply, "session_id": body.session_id}
```

```js
app.post("/chat", async (req, res) => {
  const caller = authenticate(req); // the endpoint's own auth: throws when it fails
  const reply = await benchTurn({ headers: req.headers, fromBench: caller === "veris-bench" }, () =>
    runAgent(req.body.message, req.body.session_id),
  );
  res.json({ response: reply, session_id: req.body.session_id });
});
```

Wrap all the work for the turn, every model call and tool call, and nothing
after the reply is ready. A `return` from inside the block is fine. If the auth
check is inline in the handler, put the block right after it. For a streamed
reply, wrap the generator that produces it, so the model calls run inside the
turn.

**3. On serverless hosts only** (the platform stops the process's CPU between
requests, as Cloud Run without always-on CPU, Lambda or Cloud Functions do):
flush after a bench turn, before the response returns. Python:
`bench_tracing.flush()`, which blocks for up to 2 seconds, so from async code
run it in a thread (`await asyncio.to_thread(bench_tracing.flush)`). Node:
`await flush()`, which never throws. Flush only after bench turns.

## Check it locally

Before the user deploys, prove the wiring in the agent's repository. The local
check uses a listener on this machine that reports whether a canary string
reached it:

```bash
uv run --with fastapi --with uvicorn python -c '
import fastapi, uvicorn
app = fastapi.FastAPI()
@app.post("/v1/traces")
async def traces(request: fastapi.Request):
    body = await request.body()
    print("LEAK" if b"CANARY-" in body else "bench export", flush=True)
    return {}
uvicorn.run(app, port=4399)'
```

Start the agent locally with `BENCH_TRACE_KEY=local-check` and
`BENCH_TRACE_URL=http://127.0.0.1:4399/v1/traces`, then send three turns, each
authenticated as the bench:

1. With `X-Veris-Traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
   and an ordinary question. The listener prints `bench export` within a few
   seconds.
2. Without that header, with `CANARY-1` in the message.
3. With only `traceparent` (the same value as above), with `CANARY-2` in the
   message.

Pass: the listener prints `bench export` for turn 1 (an export can take a few
seconds), and nothing at all for turns 2 and 3. It must never print `LEAK`. If
it does, the module was changed or bypassed: fix that before going on.

## If the grader sees nothing

`agent_trace_reason` stays `hosted_candidate` on an http endpoint with tracing
wired in:

| Check | How |
| --- | --- |
| The deployment has `BENCH_TRACE_KEY` | Ask the user. Without it, `configure` returns `None`/`null` and nothing is recorded. |
| The key is push-only and current | A refused key shows in the agent's logs as `bench traces not sent: HTTP 401` (or 403). |
| `from_bench` is true for the bench's requests | The route sets it from the bench's credential. A request that authenticated with another credential records nothing. |
| The model calls run inside `bench_turn` | The local check, turn 1. Work started outside it (a background task, a queue) is not sent, on purpose. |
| The instrumentor patched the SDK | The agent's startup log has no instrumentor warning, and the local check's turn 1 reaches the listener. |
| Spans arrive in time | Veris reads them 10 seconds after the conversation ends. On serverless, flush (above). |
| A proxy in front of the agent | The module reads `X-Veris-Traceparent` because proxies may rewrite `traceparent`; make sure the proxy forwards `X-Veris-Traceparent` unchanged. |
