// Send this agent's model calls to Veris Bench, for bench conversations only.
//
// Veris Bench sends each turn of a bench conversation with an `X-Veris-Traceparent`
// header. Inside `benchTurn(...)` for such a request, the agent's model-call spans are
// sent to Veris, where the grader reads them beside the transcript.
//
// - Off unless BENCH_TRACE_KEY is set. It is a push-only Veris Bench API key: keep it
//   in the deployment's secret store, never in code.
// - Nothing is sent for a request unless the route says it came from the bench
//   (`fromBench: true`, from the endpoint's own auth) and it carries the header.
// - A span is sent only if it started while that bench turn was running, inside the
//   turn's own context. Work that outlives the turn, or other requests' work, is not.
// - Only model-call spans (OpenInference) and the turn span are sent, without exception
//   details and without the process's resource attributes.
// - It sends with its own exporter: no OTEL_* setting or redirect can add a header or
//   change where the key goes, and the destination must be an https veris.ai address
//   (http only on this machine, for a local check).
// - It needs the OpenTelemetry JS 3.x packages (@opentelemetry/sdk-trace).

import { ROOT_CONTEXT, context, createContextKey, defaultTextMapGetter, isSpanContextValid, trace } from "@opentelemetry/api";
import { AsyncLocalStorageContextManager } from "@opentelemetry/context-async-hooks";
import { ExportResultCode, W3CTraceContextPropagator } from "@opentelemetry/core";
import { ProtobufTraceSerializer } from "@opentelemetry/otlp-transformer";
import { resourceFromAttributes } from "@opentelemetry/resources";
import { BatchSpanProcessor, SamplingDecision, TracerProvider } from "@opentelemetry/sdk-trace";

const HEADER = "x-veris-traceparent";
const DEFAULT_URL = "https://bench.api.veris.ai/v1/traces";
const TURN_SPAN = "bench.turn";
const TURN = createContextKey("veris-bench-turn");
const RESOURCE = resourceFromAttributes({ "service.name": "bench-agent" });

const running = new Map(); // trace id -> bench turns running in it
const accepted = new Set(); // span ids started inside a running bench turn
let provider = null;

function inTurn(parentContext, traceId) {
  return parentContext?.getValue(TURN) === traceId && (running.get(traceId) ?? 0) > 0;
}

function checkedUrl(raw) {
  const url = new URL(raw);
  const host = url.hostname;
  if (url.protocol === "https:" && (host === "veris.ai" || host.endsWith(".veris.ai"))) return url.href;
  if (url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(host)) return url.href;
  throw new Error(`BENCH_TRACE_URL must be an https veris.ai address, got ${raw}`);
}

// OTLP/HTTP protobuf to Veris, with exactly two headers.
function verisExporter(url, key) {
  return {
    export(spans, done) {
      fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/x-protobuf", Authorization: `Bearer ${key}` },
        body: ProtobufTraceSerializer.serializeRequest(spans),
        redirect: "error",
        signal: AbortSignal.timeout(10_000),
      }).then(
        (res) => {
          if (!res.ok) console.warn(`bench traces not sent: HTTP ${res.status}`);
          done({ code: res.ok ? ExportResultCode.SUCCESS : ExportResultCode.FAILED });
        },
        (err) => {
          console.warn(`bench traces not sent: ${err.name}`);
          done({ code: ExportResultCode.FAILED });
        },
      );
    },
    shutdown: async () => {},
    forceFlush: async () => {},
  };
}

// The span as Veris gets it: no exception events or status text, no resource.
function benchCopy(span) {
  return new Proxy(span, {
    get(target, prop) {
      if (prop === "resource") return RESOURCE;
      if (prop === "events") return target.events.filter((e) => e.name !== "exception");
      if (prop === "status") return { code: target.status.code };
      const value = Reflect.get(target, prop, target);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

const benchOnlySampler = {
  shouldSample(parentContext, traceId) {
    return { decision: inTurn(parentContext, traceId) ? SamplingDecision.RECORD_AND_SAMPLED : SamplingDecision.NOT_RECORD };
  },
  toString() {
    return "BenchOnlySampler";
  },
};

// The processor that sends bench spans to Veris, or null when BENCH_TRACE_KEY is unset.
// An agent that already builds its own tracer provider adds it to that provider's
// `spanProcessors` and passes the provider to `configure`. Throws if BENCH_TRACE_URL
// isn't a Veris address.
export function benchSpanProcessor() {
  const key = process.env.BENCH_TRACE_KEY;
  if (!key) return null;
  // Small batches: Veris refuses a request over 4 MB, and reads the spans 10 s after the
  // conversation ends.
  const inner = new BatchSpanProcessor({
    exporter: verisExporter(checkedUrl(process.env.BENCH_TRACE_URL ?? DEFAULT_URL), key),
    scheduledDelayMillis: 1000,
    maxExportBatchSize: 32,
  });
  return {
    onStart(span, parentContext) {
      const { traceId, spanId } = span.spanContext();
      if (inTurn(parentContext, traceId)) accepted.add(spanId);
    },
    onEnd(span) {
      if (!accepted.delete(span.spanContext().spanId)) return;
      if (span.name === TURN_SPAN || span.attributes["openinference.span.kind"]) inner.onEnd(benchCopy(span));
    },
    shutdown: () => inner.shutdown(),
    forceFlush: () => inner.forceFlush(),
  };
}

// Start sending bench traces, once, at startup. Returns the provider to hand the agent's
// OpenInference instrumentation, or null when BENCH_TRACE_KEY is unset.
export function configure({ provider: own } = {}) {
  if (!process.env.BENCH_TRACE_KEY) return null;
  provider = own ?? new TracerProvider({ sampler: benchOnlySampler, resource: RESOURCE, spanProcessors: [benchSpanProcessor()] });
  // The turn's context has to follow the agent's awaits. This registers a context
  // manager only when the process has none; an existing one is kept.
  context.setGlobalContextManager(new AsyncLocalStorageContextManager().enable());
  return provider;
}

function headerValue(headers) {
  const value = typeof headers.get === "function" ? headers.get(HEADER) : headers[HEADER];
  return Array.isArray(value) ? value[0] : value;
}

// Run one request's agent work, `fn`, in the bench's trace. `fromBench` is the route's own
// answer to "did this request authenticate as the bench?"; when it is false, or the
// request has no X-Veris-Traceparent, `fn` just runs. `headers` is a Node or Express
// request's `headers`, or a fetch `Headers`.
export async function benchTurn({ headers, fromBench }, fn) {
  const value = provider && fromBench ? headerValue(headers) : undefined;
  const ctx = value
    ? new W3CTraceContextPropagator().extract(ROOT_CONTEXT, { traceparent: value }, defaultTextMapGetter)
    : undefined;
  const parent = ctx ? trace.getSpanContext(ctx) : undefined;
  if (!parent || !isSpanContextValid(parent)) return fn();
  const { traceId } = parent;
  running.set(traceId, (running.get(traceId) ?? 0) + 1);
  try {
    return await provider.getTracer("bench").startActiveSpan(TURN_SPAN, {}, ctx.setValue(TURN, traceId), async (span) => {
      try {
        return await fn();
      } finally {
        span.end();
      }
    });
  } finally {
    const left = running.get(traceId) - 1;
    if (left) running.set(traceId, left);
    else running.delete(traceId);
  }
}

// Send what is buffered now. Await it after a bench turn, before the response returns,
// on a host that stops the process's CPU between requests (serverless). It never
// throws, and gives up after two seconds.
export async function flush() {
  if (!provider) return;
  let timer;
  await Promise.race([
    provider.forceFlush().catch(() => {}),
    new Promise((resolve) => {
      timer = setTimeout(resolve, 2000);
    }),
  ]);
  clearTimeout(timer);
}
