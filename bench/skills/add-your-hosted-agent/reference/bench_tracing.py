"""Send this agent's model calls to Veris Bench, for bench conversations only.

Veris Bench sends each turn of a bench conversation with an `X-Veris-Traceparent`
header. Inside `bench_turn(...)` for such a request, the model calls the agent makes
are recorded and sent to Veris, where the grader reads them beside the transcript.

- Off unless `BENCH_TRACE_KEY` is set. It is a push-only Veris Bench API key: keep it
  in the deployment's secret store, never in code.
- A span leaves the process only when its trace id came from an
  `X-Veris-Traceparent` header. Every other request's model calls stay where they
  were, whatever other tracing the agent runs.
- The global tracer provider and the `OTEL_*` settings are never touched, so the
  agent's own telemetry is unchanged.
"""

import os
import threading
import time
from collections.abc import Iterator, Mapping
from contextlib import contextmanager

from opentelemetry import trace
from opentelemetry.context import Context
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import ReadableSpan, Span, SpanProcessor, TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.trace.sampling import Decision, Sampler, SamplingResult
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

HEADER = "x-veris-traceparent"
DEFAULT_URL = "https://bench.api.veris.ai/v1/traces"
# A bench conversation's turns share one trace id; it stays accepted this long after a turn.
BENCH_TRACE_TTL_S = 900.0

_lock = threading.Lock()
_bench_traces: dict[int, float] = {}
_provider: TracerProvider | None = None


def _is_bench(trace_id: int) -> bool:
    with _lock:
        return _bench_traces.get(trace_id, 0.0) > time.monotonic()


def _remember(trace_id: int) -> None:
    now = time.monotonic()
    with _lock:
        for stale in [t for t, until in _bench_traces.items() if until <= now]:
            del _bench_traces[stale]
        _bench_traces[trace_id] = now + BENCH_TRACE_TTL_S


class _BenchOnlySampler(Sampler):
    """Records a span only inside a bench request's trace."""

    def should_sample(
        self, parent_context, trace_id, name, kind=None, attributes=None, links=None, trace_state=None
    ) -> SamplingResult:
        parent = trace.get_current_span(parent_context).get_span_context()
        if _is_bench(trace_id):
            return SamplingResult(Decision.RECORD_AND_SAMPLE, attributes, parent.trace_state)
        return SamplingResult(Decision.DROP, None, parent.trace_state)

    def get_description(self) -> str:
        return "BenchOnlySampler"


class _BenchOnlyExport(SpanProcessor):
    """Hands a span to the Veris exporter only if it belongs to a bench request's trace."""

    def __init__(self, inner: SpanProcessor) -> None:
        self._inner = inner

    def on_start(self, span: Span, parent_context: Context | None = None) -> None:
        if _is_bench(span.context.trace_id):
            self._inner.on_start(span, parent_context)

    def on_end(self, span: ReadableSpan) -> None:
        if _is_bench(span.context.trace_id):
            self._inner.on_end(span)

    def shutdown(self) -> None:
        self._inner.shutdown()

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return self._inner.force_flush(timeout_millis)


def configure(provider: TracerProvider | None = None) -> TracerProvider | None:
    """Start sending bench traces, once, at startup. Give it the agent's own
    TracerProvider if the agent already traces its model calls; otherwise it makes a
    private one. Returns the provider to hand the agent's OpenInference instrumentor, or
    None when BENCH_TRACE_KEY is unset."""
    global _provider
    key = os.environ.get("BENCH_TRACE_KEY")
    if not key:
        return None
    exporter = OTLPSpanExporter(
        endpoint=os.environ.get("BENCH_TRACE_URL", DEFAULT_URL),
        headers={"Authorization": f"Bearer {key}"},
        timeout=10,
    )
    _provider = provider or TracerProvider(sampler=_BenchOnlySampler())
    # Small batches: Veris refuses a request over 4 MB, and reads the spans 10 s after
    # the conversation ends.
    _provider.add_span_processor(
        _BenchOnlyExport(
            BatchSpanProcessor(exporter, schedule_delay_millis=1000, max_export_batch_size=32)
        )
    )
    return _provider


@contextmanager
def bench_turn(headers: Mapping[str, str]) -> Iterator[None]:
    """Run one request's agent work in the bench's trace when the request carries
    X-Veris-Traceparent; otherwise do nothing. Use it after the request has passed the
    endpoint's own auth check. `headers` must look names up case-insensitively, as
    Starlette, Flask and Django request headers do."""
    value = headers.get(HEADER) if _provider is not None else None
    ctx = TraceContextTextMapPropagator().extract({"traceparent": value}) if value else None
    parent = trace.get_current_span(ctx).get_span_context() if ctx is not None else None
    if parent is None or not parent.is_valid:
        yield
        return
    _remember(parent.trace_id)
    with _provider.get_tracer(__name__).start_as_current_span("bench.turn", context=ctx):
        yield


def flush(timeout_millis: int = 5000) -> None:
    """Send what is buffered now. Call it before each response returns on a host that
    stops the process's CPU between requests (serverless). It blocks: from async code,
    run it in a thread."""
    if _provider is not None:
        _provider.force_flush(timeout_millis)
