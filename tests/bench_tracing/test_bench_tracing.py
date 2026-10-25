"""bench_tracing.py sends a bench turn's model calls to Veris, and nothing else.

Each case runs the module, unchanged, in a fresh interpreter against a local listener,
and checks the raw request bodies and headers it received. Run from the repository root:

  uv run --with opentelemetry-sdk --with opentelemetry-exporter-otlp-proto-common \
    python tests/bench_tracing/test_bench_tracing.py
"""

import json
import os
import subprocess
import sys
import textwrap
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

MODULE_DIR = Path(__file__).resolve().parents[2] / "bench/skills/add-your-hosted-agent/reference"
TRACE = "4bf92f3577b34da6a3ce929d0e0e4736"
BENCH = {"x-veris-traceparent": f"00-{TRACE}-00f067aa0ba902b7-01", "traceparent": f"00-{TRACE}-00f067aa0ba902b7-01"}

PRELUDE = f"""
import asyncio, sys, time
sys.path.insert(0, {str(MODULE_DIR)!r})
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
import bench_tracing

BENCH = {BENCH!r}

class Headers(dict):
    def get(self, key, default=None):
        return super().get(key.lower(), default)

def model_call(tracer, text):
    with tracer.start_as_current_span("ChatCompletion") as span:
        span.set_attribute("openinference.span.kind", "LLM")
        span.set_attribute("input.value", text)
"""


class Sink(BaseHTTPRequestHandler):
    received: list[dict] = []
    status = 200

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        Sink.received.append({"headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
        self.send_response(Sink.status)
        self.end_headers()

    def log_message(self, *args):
        pass


def run(case: str, env: dict | None = None) -> tuple[list[dict], subprocess.CompletedProcess]:
    """Run one case's code in a fresh interpreter; return what reached the listener."""
    Sink.received = []
    server = HTTPServer(("127.0.0.1", 0), Sink)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    full_env = {
        **os.environ,
        "BENCH_TRACE_KEY": "bench-key-XYZ",
        "BENCH_TRACE_URL": f"http://127.0.0.1:{server.server_port}/v1/traces",
        **(env or {}),
    }
    code = PRELUDE + textwrap.dedent(case) + "\nbench_tracing.flush(5000)\n"
    proc = subprocess.run([sys.executable, "-c", code], env=full_env, capture_output=True, text=True, timeout=60)
    server.shutdown()
    return Sink.received, proc


def body(received: list[dict]) -> bytes:
    return b"".join(r["body"] for r in received)


def check(name: str, ok: bool, detail: str = "") -> bool:
    print(f"{'ok  ' if ok else 'FAIL'}  {name}{'' if ok else ': ' + detail}")
    return ok


def main() -> int:
    results = []

    got, proc = run(
        """
        provider = bench_tracing.configure()
        with bench_tracing.bench_turn(Headers(BENCH), from_bench=True):
            model_call(provider.get_tracer("t"), "CANARY-BENCH")
        """,
        env={
            "OTEL_EXPORTER_OTLP_HEADERS": "x-honeycomb-team=CANARY-VENDOR-KEY",
            "OTEL_EXPORTER_OTLP_TRACES_HEADERS": "dd-api-key=CANARY-VENDOR-KEY",
            "OTEL_RESOURCE_ATTRIBUTES": "k8s.cluster.name=CANARY-RESOURCE",
            "OTEL_SERVICE_NAME": "CANARY-SERVICE",
        },
    )
    sent = body(got)
    headers = {k for r in got for k in r["headers"]}
    results += [
        check("a bench turn's model call is sent, in the bench trace", b"CANARY-BENCH" in sent and bytes.fromhex(TRACE) in sent, proc.stderr[-500:]),
        check("the turn span is sent", b"bench.turn" in sent),
        check("only the bench key authorizes the export", all(r["headers"].get("authorization") == "Bearer bench-key-XYZ" for r in got) and bool(got)),
        check("no OTEL_* header reaches Veris", "x-honeycomb-team" not in headers and "dd-api-key" not in headers, str(headers)),
        check("no OTEL_* resource attribute reaches Veris", b"CANARY-RESOURCE" not in sent and b"CANARY-SERVICE" not in sent),
    ]

    got, proc = run(
        """
        provider = bench_tracing.configure()
        tracer = provider.get_tracer("t")
        with bench_tracing.bench_turn(Headers(), from_bench=True):
            model_call(tracer, "CANARY-NO-HEADER")
        with bench_tracing.bench_turn(Headers(BENCH), from_bench=False):
            model_call(tracer, "CANARY-NOT-FROM-BENCH")
        model_call(tracer, "CANARY-OUTSIDE")
        """
    )
    results += [
        check("a request without X-Veris-Traceparent sends nothing", b"CANARY-NO-HEADER" not in body(got), proc.stderr[-500:]),
        check("from_bench=False sends nothing", b"CANARY-NOT-FROM-BENCH" not in body(got)),
        check("a model call outside any turn sends nothing", b"CANARY-OUTSIDE" not in body(got)),
    ]

    got, proc = run(
        """
        own_spans = InMemorySpanExporter()
        own = TracerProvider()
        own.add_span_processor(SimpleSpanProcessor(own_spans))
        bench_tracing.configure(own)
        tracer = own.get_tracer("t")
        # The agent's own framework tracing continues `traceparent`, with no bench turn.
        ctx = TraceContextTextMapPropagator().extract({"traceparent": BENCH["traceparent"]})
        with tracer.start_as_current_span("POST /chat", context=ctx):
            model_call(tracer, "CANARY-TRACEPARENT-ONLY")
        with bench_tracing.bench_turn(Headers(BENCH), from_bench=True):
            with tracer.start_as_current_span("SELECT") as db:
                db.set_attribute("db.statement", "SELECT * FROM orders WHERE email = 'CANARY-DB'")
            model_call(tracer, "CANARY-BENCH")
        print("own spans", len(own_spans.get_finished_spans()))
        """
    )
    sent = body(got)
    results += [
        check("a request carrying only a live traceparent sends nothing", b"CANARY-TRACEPARENT-ONLY" not in sent, proc.stderr[-500:]),
        check("with the agent's provider, a bench model call is sent", b"CANARY-BENCH" in sent),
        check("with the agent's provider, other spans in the turn are not sent", b"CANARY-DB" not in sent),
        check("the agent's own exporter still gets every span", "own spans 5" in proc.stdout, proc.stdout),
    ]

    got, proc = run(
        """
        async def main():
            provider = bench_tracing.configure()
            tracer = provider.get_tracer("t")
            queue = asyncio.Queue()

            async def worker():  # started lazily, by whichever request comes first
                while True:
                    text = await queue.get()
                    model_call(tracer, text)
                    queue.task_done()

            with bench_tracing.bench_turn(Headers(BENCH), from_bench=True):
                asyncio.create_task(worker())
                model_call(tracer, "CANARY-BENCH")
            await queue.put("CANARY-LATER-USER")
            await queue.join()

        asyncio.run(main())
        """
    )
    results += [
        check("work that outlives the turn sends nothing", b"CANARY-LATER-USER" not in body(got) and b"CANARY-BENCH" in body(got), proc.stderr[-500:]),
    ]

    got, proc = run(
        """
        provider = bench_tracing.configure()
        try:
            with bench_tracing.bench_turn(Headers(BENCH), from_bench=True):
                model_call(provider.get_tracer("t"), "CANARY-BENCH")
                raise RuntimeError("postgres://user:CANARY-PASSWORD@10.0.3.4/orders")
        except RuntimeError:
            pass
        """
    )
    results += [
        check("an exception's text is not sent", b"CANARY-PASSWORD" not in body(got) and b"CANARY-BENCH" in body(got), proc.stderr[-500:]),
    ]

    for url in ("http://bench.api.veris.ai/v1/traces", "https://collector.example.com/v1/traces", "https://veris.ai.example.com/v1/traces"):
        _, proc = run("bench_tracing.configure()", env={"BENCH_TRACE_URL": url})
        results.append(check(f"refuses BENCH_TRACE_URL {url}", proc.returncode != 0 and "BENCH_TRACE_URL must be" in proc.stderr, proc.stderr[-300:]))

    Sink.status = 503
    got, proc = run(
        """
        provider = bench_tracing.configure()
        with bench_tracing.bench_turn(Headers(BENCH), from_bench=True):
            model_call(provider.get_tracer("t"), "CANARY-BENCH")
        """
    )
    Sink.status = 200
    results.append(check("a refused export doesn't fail the agent, nor log the key", proc.returncode == 0 and "bench-key-XYZ" not in proc.stderr, proc.stderr[-300:]))

    _, proc = run(
        """
        provider = bench_tracing.configure()
        print("configured", provider is not None)
        """,
        env={"BENCH_TRACE_KEY": ""},
    )
    results.append(check("without BENCH_TRACE_KEY nothing is configured", "configured False" in proc.stdout, proc.stdout + proc.stderr[-300:]))

    print(json.dumps({"passed": sum(results), "failed": len(results) - sum(results)}))
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
