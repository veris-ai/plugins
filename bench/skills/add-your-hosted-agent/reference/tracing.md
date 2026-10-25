# Let the grader see a hosted agent's model calls

For a hosted http endpoint, each turn's request carries an `X-Veris-Traceparent`
header (and a `traceparent` header with the same value). If the agent's
model-call spans belong to that trace and reach Veris within 10 seconds of the
conversation's end, the grader reads them beside the transcript: the tool calls,
their results, the system prompt, token counts.

`bench_tracing.py` and `bench_tracing.mjs` do this, and only this. Copy the one
for the agent's language into the agent, next to its entry point, unchanged.

## What the module guarantees

These are why the module exists instead of a few lines of OpenTelemetry setup.
Don't weaken them when you wire it in:

- **Off unless `BENCH_TRACE_KEY` is set.** No key, no export, nothing recorded.
- **Bench conversations only.** A span leaves the process only if its trace id
  came from an `X-Veris-Traceparent` header. Other requests' model calls are
  never sent, even when the agent has its own OpenTelemetry tracing that samples
  everything, and even when a caller sends its own `traceparent`.
- **The agent's own telemetry is untouched.** No global tracer provider is set,
  no `OTEL_*` variable is read or changed, and an existing provider keeps its
  own exporters.
- **Only to Veris.** Spans go to `BENCH_TRACE_URL`, default
  `https://bench.api.veris.ai/v1/traces`, over HTTPS, with `BENCH_TRACE_KEY`.

## Security rules

- `BENCH_TRACE_KEY` is a push-only key, in the deployment's secret store. Never
  in code, a committed file, a Dockerfile, a log line or a command line. Never
  `VERIS_API_KEY`, which can change the user's benches.
- Call `bench_turn` / `benchTurn` only after the request has passed the
  endpoint's own auth check, so an unauthenticated caller can't make the agent
  record anything.
- Bench spans hold the bench conversation in full: prompts, tool arguments,
  tool results. If the agent puts a secret into a prompt or a tool result (an
  internal token, a connection string), stop and tell the user: it would be
  sent. Don't mask it yourself by editing spans.
- Don't set `BENCH_TRACE_URL` unless the user gives you another Veris address.

## Packages

Add them with the project's package manager, so the lockfile records the
versions:

| Language | Packages |
| --- | --- |
| Python | `opentelemetry-sdk`, `opentelemetry-exporter-otlp-proto-http`, and the OpenInference instrumentor for the agent's model SDK |
| Node | `@opentelemetry/api`, `@opentelemetry/core`, `@opentelemetry/context-async-hooks`, `@opentelemetry/sdk-trace`, `@opentelemetry/exporter-trace-otlp-proto`, and the OpenInference instrumentation for the agent's model SDK |

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
warning at startup.

**Node: one OpenTelemetry release line.** The `@opentelemetry/*` packages must
agree on `@opentelemetry/api`. If npm stops with `ERESOLVE` on
`@opentelemetry/api`, the newest packages come from two release lines. Install
the line that `@opentelemetry/sdk-trace` belongs to (`npm view
@opentelemetry/sdk-trace dependencies` lists its `@opentelemetry/core`), never
`--force`. An agent already on the 2.x line uses `@opentelemetry/sdk-trace-base`:
change the module's import as its comment says.

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
shows.

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

**2. Around each request's agent work**, after the auth check:

```python
@app.post("/chat")
async def chat(body: ChatIn, request: Request) -> dict:
    check_auth(request)
    with bench_tracing.bench_turn(request.headers):
        reply = await run_agent(body.message, body.session_id)
    return {"response": reply, "session_id": body.session_id}
```

```js
app.post("/chat", async (req, res) => {
  checkAuth(req);
  const reply = await benchTurn(req.headers, () => runAgent(req.body.message, req.body.session_id));
  res.json({ response: reply, session_id: req.body.session_id });
});
```

Wrap all the work for the turn, every model call and tool call, and nothing
after the reply is ready. A `return` from inside the block is fine. If the auth
check is inline in the handler, put the block right after it. For a streamed reply, wrap the generator that produces
it, so the model calls run inside the turn.

**3. On serverless hosts only** (the platform stops the process's CPU between
requests, as Cloud Run without always-on CPU, Lambda or Cloud Functions do):
flush before the response returns. Python: `bench_tracing.flush()`, which blocks,
so from async code run it in a thread (`await asyncio.to_thread(bench_tracing.flush)`).
Node: `await flush()`.

## Check it locally

Before the user deploys, prove the wiring in the agent's repository:

1. Start the agent locally with `BENCH_TRACE_KEY=local-check` and
   `BENCH_TRACE_URL=http://127.0.0.1:4318/v1/traces`, and run a listener that
   logs what reaches it, for example
   `uv run --with fastapi --with uvicorn python -c 'import uvicorn,fastapi; a=fastapi.FastAPI(); a.post("/v1/traces")(lambda: print("export received") or {}); uvicorn.run(a, port=4318)'`.
2. Send one turn **without** `X-Veris-Traceparent`. Nothing reaches the
   listener.
3. Send one turn **with** `X-Veris-Traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`.
   An export reaches the listener within a few seconds.

If step 2 sends anything, the module was changed or bypassed: fix that before
going on.

## If the grader sees nothing

`agent_trace_reason` stays `hosted_candidate` on an http endpoint with tracing
wired in:

| Check | How |
| --- | --- |
| The deployment has `BENCH_TRACE_KEY` | Ask the user. Without it, `configure` returns `None`/`null` and nothing is recorded. |
| The key is push-only and current | A refused key shows in the agent's logs as an OTLP export error (401 or 403). |
| The model calls run inside `bench_turn` | The local check, step 3. Work started outside it (a background task, a queue) is in another trace. |
| The instrumentor patched the SDK | The agent's startup log has no instrumentor warning; the local check's export holds spans with `openinference.span.kind`. |
| Spans arrive in time | Veris reads them 10 seconds after the conversation ends. On serverless, flush (above). |
| A proxy in front of the agent | The module reads `X-Veris-Traceparent` because proxies may rewrite `traceparent`; make sure the proxy forwards `X-Veris-Traceparent` unchanged. |
