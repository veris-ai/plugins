// One case per process, against an unchanged copy of bench_tracing.mjs (see test_bench_tracing.mjs).
import { context, trace, ROOT_CONTEXT, defaultTextMapGetter } from "@opentelemetry/api";
import { W3CTraceContextPropagator } from "@opentelemetry/core";
import { InMemorySpanExporter, SimpleSpanProcessor, TracerProvider } from "@opentelemetry/sdk-trace";
import * as bench from "./_bench_tracing.mjs";

const TRACE = "4bf92f3577b34da6a3ce929d0e0e4736";
const BENCH = { "x-veris-traceparent": `00-${TRACE}-00f067aa0ba902b7-01`, traceparent: `00-${TRACE}-00f067aa0ba902b7-01` };

function modelCall(tracer, text) {
  tracer.startActiveSpan("ChatCompletion", (span) => {
    span.setAttribute("openinference.span.kind", "LLM");
    span.setAttribute("input.value", text);
    span.end();
  });
}

const cases = {
  async bench() {
    const provider = bench.configure();
    await bench.benchTurn({ headers: BENCH, fromBench: true }, async () => modelCall(provider.getTracer("t"), "CANARY-BENCH"));
  },
  async notBench() {
    const tracer = bench.configure().getTracer("t");
    await bench.benchTurn({ headers: {}, fromBench: true }, async () => modelCall(tracer, "CANARY-NO-HEADER"));
    await bench.benchTurn({ headers: BENCH, fromBench: false }, async () => modelCall(tracer, "CANARY-NOT-FROM-BENCH"));
    modelCall(tracer, "CANARY-OUTSIDE");
  },
  async existing() {
    const own = new InMemorySpanExporter();
    const provider = new TracerProvider({ spanProcessors: [new SimpleSpanProcessor({ exporter: own }), bench.benchSpanProcessor()] });
    bench.configure({ provider });
    const tracer = provider.getTracer("t");
    // The agent's own framework tracing continues `traceparent`, with no bench turn.
    const ctx = new W3CTraceContextPropagator().extract(ROOT_CONTEXT, { traceparent: BENCH.traceparent }, defaultTextMapGetter);
    await tracer.startActiveSpan("POST /chat", {}, ctx, async (span) => {
      modelCall(tracer, "CANARY-TRACEPARENT-ONLY");
      span.end();
    });
    await bench.benchTurn({ headers: BENCH, fromBench: true }, async () => {
      tracer.startActiveSpan("SELECT", (db) => {
        db.setAttribute("db.statement", "SELECT * FROM orders WHERE email = 'CANARY-DB'");
        db.end();
      });
      modelCall(tracer, "CANARY-BENCH");
    });
    console.log(`own spans ${own.getFinishedSpans().length}`);
  },
  async lazyWorker() {
    const tracer = bench.configure().getTracer("t");
    const queue = [];
    let worker = null;
    const submit = (text) => {
      queue.push(text);
      // Started lazily, by whichever request comes first.
      worker ??= setInterval(() => {
        while (queue.length) modelCall(tracer, queue.shift());
      }, 50);
    };
    await bench.benchTurn({ headers: BENCH, fromBench: true }, async () => {
      submit("CANARY-BENCH");
      await new Promise((r) => setTimeout(r, 150));
    });
    submit("CANARY-LATER-USER");
    await new Promise((r) => setTimeout(r, 150));
    clearInterval(worker);
  },
  async exception() {
    const provider = bench.configure();
    await bench
      .benchTurn({ headers: BENCH, fromBench: true }, async () => {
        modelCall(provider.getTracer("t"), "CANARY-BENCH");
        throw new Error("postgres://user:CANARY-PASSWORD@10.0.3.4/orders");
      })
      .catch(() => {});
  },
  async badUrl() {
    bench.configure();
  },
  async refused() {
    const provider = bench.configure();
    await bench.benchTurn({ headers: BENCH, fromBench: true }, async () => modelCall(provider.getTracer("t"), "CANARY-BENCH"));
  },
  async noKey() {
    console.log(`configured ${bench.configure() !== null}`);
  },
};

await cases[process.argv[2]]();
await bench.flush();
console.log("done");
