// Send this agent's model calls to Veris Bench, for bench conversations only.
//
// Veris Bench sends each turn of a bench conversation with an `X-Veris-Traceparent`
// header. Inside `benchTurn(...)` for such a request, the model calls the agent makes
// are recorded and sent to Veris, where the grader reads them beside the transcript.
//
// - Off unless BENCH_TRACE_KEY is set. It is a push-only Veris Bench API key: keep it
//   in the deployment's secret store, never in code.
// - A span leaves the process only when its trace id came from an
//   `X-Veris-Traceparent` header. Every other request's model calls stay where they
//   were, whatever other tracing the agent runs.
// - The global tracer provider and the OTEL_* settings are never touched, so the
//   agent's own telemetry is unchanged.

import { ROOT_CONTEXT, context, defaultTextMapGetter, isSpanContextValid, trace } from "@opentelemetry/api";
import { AsyncLocalStorageContextManager } from "@opentelemetry/context-async-hooks";
import { W3CTraceContextPropagator } from "@opentelemetry/core";
import { OTLPTraceExporter } from "@opentelemetry/exporter-trace-otlp-proto";
// On the OpenTelemetry JS 2.x line these come from @opentelemetry/sdk-trace-base, where
// TracerProvider is named BasicTracerProvider and BatchSpanProcessor takes
// (exporter, options) instead of one options object.
import { BatchSpanProcessor, SamplingDecision, TracerProvider } from "@opentelemetry/sdk-trace";

const HEADER = "x-veris-traceparent";
const DEFAULT_URL = "https://bench.api.veris.ai/v1/traces";
// A bench conversation's turns share one trace id; it stays accepted this long after a turn.
const BENCH_TRACE_TTL_MS = 900_000;

const benchTraces = new Map();
let provider = null;

function isBench(traceId) {
  return (benchTraces.get(traceId) ?? 0) > Date.now();
}

function remember(traceId) {
  const now = Date.now();
  for (const [id, until] of benchTraces) if (until <= now) benchTraces.delete(id);
  benchTraces.set(traceId, now + BENCH_TRACE_TTL_MS);
}

const benchOnlySampler = {
  shouldSample(_context, traceId) {
    return { decision: isBench(traceId) ? SamplingDecision.RECORD_AND_SAMPLED : SamplingDecision.NOT_RECORD };
  },
  toString() {
    return "BenchOnlySampler";
  },
};

// The processor that sends bench spans to Veris, or null when BENCH_TRACE_KEY is unset.
// An agent that already builds its own tracer provider adds it to that provider's
// `spanProcessors` and passes the provider to `configure`.
export function benchSpanProcessor() {
  const key = process.env.BENCH_TRACE_KEY;
  if (!key) return null;
  const exporter = new OTLPTraceExporter({
    url: process.env.BENCH_TRACE_URL ?? DEFAULT_URL,
    headers: { Authorization: `Bearer ${key}` },
    timeoutMillis: 10_000,
  });
  // Small batches: Veris refuses a request over 4 MB, and reads the spans 10 s after the
  // conversation ends.
  const inner = new BatchSpanProcessor({ exporter, scheduledDelayMillis: 1000, maxExportBatchSize: 32 });
  return {
    onStart(span, parentContext) {
      if (isBench(span.spanContext().traceId)) inner.onStart(span, parentContext);
    },
    onEnd(span) {
      if (isBench(span.spanContext().traceId)) inner.onEnd(span);
    },
    shutdown: () => inner.shutdown(),
    forceFlush: () => inner.forceFlush(),
  };
}

// Start sending bench traces, once, at startup. Returns the provider to hand the agent's
// OpenInference instrumentation, or null when BENCH_TRACE_KEY is unset.
export function configure({ provider: own } = {}) {
  if (!process.env.BENCH_TRACE_KEY) return null;
  provider = own ?? new TracerProvider({ sampler: benchOnlySampler, spanProcessors: [benchSpanProcessor()] });
  // benchTurn's trace has to follow the agent's awaits. This registers a context manager
  // only when the process has none; an existing one is kept.
  context.setGlobalContextManager(new AsyncLocalStorageContextManager().enable());
  return provider;
}

function headerValue(headers) {
  const value = typeof headers.get === "function" ? headers.get(HEADER) : headers[HEADER];
  return Array.isArray(value) ? value[0] : value;
}

// Run one request's agent work, `fn`, in the bench's trace when the request carries
// X-Veris-Traceparent; otherwise just run it. Use it after the request has passed the
// endpoint's own auth check. `headers` is a Node or Express request's `headers`, or a
// fetch `Headers`.
export async function benchTurn(headers, fn) {
  const value = provider ? headerValue(headers) : undefined;
  const ctx = value
    ? new W3CTraceContextPropagator().extract(ROOT_CONTEXT, { traceparent: value }, defaultTextMapGetter)
    : undefined;
  const parent = ctx ? trace.getSpanContext(ctx) : undefined;
  if (!parent || !isSpanContextValid(parent)) return fn();
  remember(parent.traceId);
  return provider.getTracer("bench").startActiveSpan("bench.turn", {}, ctx, async (span) => {
    try {
      return await fn();
    } finally {
      span.end();
    }
  });
}

// Send what is buffered now. Await it before each response returns on a host that stops
// the process's CPU between requests (serverless).
export async function flush() {
  if (provider) await provider.forceFlush();
}
