"""Send this agent's model calls to Veris Bench, for bench conversations only.

Veris Bench sends each turn of a bench conversation with an `X-Veris-Traceparent`
header. Inside `bench_turn(...)` for such a request, the agent's model-call spans are
sent to Veris, where the grader reads them beside the transcript.

- Off unless `BENCH_TRACE_KEY` is set. It is a push-only Veris Bench API key: keep it
  in the deployment's secret store, never in code.
- Nothing is sent for a request unless the route says it came from the bench
  (`from_bench=True`, from the endpoint's own auth) and it carries the header.
- A span is sent only if it started while that bench turn was running, inside the
  turn's own context. Work that outlives the turn, or other requests' work, is not.
- Only model-call spans (OpenInference) and the turn span are sent, without exception
  details and without the process's resource attributes.
- It sends with its own exporter: no `OTEL_*` setting, proxy credential or redirect
  can add a header or change where the key goes, and the destination must be an
  `https` veris.ai address (`http` only on this machine, for a local check).
"""

import logging
import os
import threading
import urllib.error
import urllib.request
from collections.abc import Iterator, Mapping, Sequence
from contextlib import contextmanager
from urllib.parse import urlsplit

from opentelemetry import context as otel_context
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.common.trace_encoder import encode_spans
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import ReadableSpan, Span, SpanProcessor, TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor, SpanExporter, SpanExportResult
from opentelemetry.sdk.trace.sampling import Decision, Sampler, SamplingResult
from opentelemetry.trace import Status
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator

HEADER = "x-veris-traceparent"
DEFAULT_URL = "https://bench.api.veris.ai/v1/traces"
TURN_SPAN = "bench.turn"
_TURN = otel_context.create_key("veris-bench-turn")
_RESOURCE = Resource({"service.name": "bench-agent"})
_log = logging.getLogger(__name__)

_lock = threading.Lock()
_running: dict[int, int] = {}  # trace id -> bench turns running in it
_accepted: set[int] = set()  # span ids started inside a running bench turn
_provider: TracerProvider | None = None


def _in_turn(parent_context, trace_id: int) -> bool:
    if otel_context.get_value(_TURN, parent_context) != trace_id:
        return False
    with _lock:
        return _running.get(trace_id, 0) > 0


def _checked_url(url: str) -> str:
    parts = urlsplit(url)
    host = parts.hostname or ""
    if parts.scheme == "https" and (host == "veris.ai" or host.endswith(".veris.ai")):
        return url
    if parts.scheme == "http" and host in ("127.0.0.1", "localhost", "::1"):
        return url
    raise ValueError(f"BENCH_TRACE_URL must be an https veris.ai address, got {url!r}")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


class _VerisExporter(SpanExporter):
    """OTLP/HTTP protobuf to Veris, with exactly two headers."""

    def __init__(self, url: str, key: str) -> None:
        self._url, self._key = url, key
        self._opener = urllib.request.build_opener(_NoRedirect)

    def export(self, spans: Sequence[ReadableSpan]) -> SpanExportResult:
        request = urllib.request.Request(
            self._url,
            data=encode_spans(spans).SerializeToString(),
            method="POST",
            headers={"Content-Type": "application/x-protobuf", "Authorization": f"Bearer {self._key}"},
        )
        try:
            with self._opener.open(request, timeout=10) as response:
                response.read()
        except (urllib.error.URLError, OSError) as err:
            _log.warning("bench traces not sent: %s", err)
            return SpanExportResult.FAILURE
        return SpanExportResult.SUCCESS

    def shutdown(self) -> None:
        pass

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return True


def _bench_copy(span: ReadableSpan) -> ReadableSpan:
    """The span as Veris gets it: no exception events or status text, no resource."""
    return ReadableSpan(
        name=span.name,
        context=span.context,
        parent=span.parent,
        resource=_RESOURCE,
        attributes=span.attributes,
        events=[e for e in span.events if e.name != "exception"],
        links=span.links,
        kind=span.kind,
        status=Status(span.status.status_code),
        start_time=span.start_time,
        end_time=span.end_time,
        instrumentation_scope=span.instrumentation_scope,
    )


class _BenchOnlySampler(Sampler):
    """Records a span only inside a running bench turn."""

    def should_sample(
        self, parent_context, trace_id, name, kind=None, attributes=None, links=None, trace_state=None
    ) -> SamplingResult:
        parent = trace.get_current_span(parent_context).get_span_context()
        if _in_turn(parent_context, trace_id):
            return SamplingResult(Decision.RECORD_AND_SAMPLE, attributes, parent.trace_state)
        return SamplingResult(Decision.DROP, None, parent.trace_state)

    def get_description(self) -> str:
        return "BenchOnlySampler"


class _BenchOnlyExport(SpanProcessor):
    """Hands Veris the model-call spans that started inside a running bench turn."""

    def __init__(self, inner: SpanProcessor) -> None:
        self._inner = inner

    def on_start(self, span: Span, parent_context=None) -> None:
        if _in_turn(parent_context, span.context.trace_id):
            with _lock:
                _accepted.add(span.context.span_id)

    def on_end(self, span: ReadableSpan) -> None:
        with _lock:
            if span.context.span_id not in _accepted:
                return
            _accepted.discard(span.context.span_id)
        if span.name == TURN_SPAN or (span.attributes or {}).get("openinference.span.kind"):
            self._inner.on_end(_bench_copy(span))

    def shutdown(self) -> None:
        self._inner.shutdown()

    def force_flush(self, timeout_millis: int = 30000) -> bool:
        return self._inner.force_flush(timeout_millis)


def configure(provider: TracerProvider | None = None) -> TracerProvider | None:
    """Start sending bench traces, once, at startup. Give it the agent's own
    TracerProvider if the agent already traces its model calls; otherwise it makes a
    private one. Returns the provider to hand the agent's OpenInference instrumentor, or
    None when BENCH_TRACE_KEY is unset. Raises if BENCH_TRACE_URL isn't a Veris address."""
    global _provider
    key = os.environ.get("BENCH_TRACE_KEY")
    if not key:
        return None
    exporter = _VerisExporter(_checked_url(os.environ.get("BENCH_TRACE_URL", DEFAULT_URL)), key)
    _provider = provider or TracerProvider(sampler=_BenchOnlySampler(), resource=_RESOURCE)
    # Small batches: Veris refuses a request over 4 MB, and reads the spans 10 s after
    # the conversation ends.
    _provider.add_span_processor(
        _BenchOnlyExport(
            BatchSpanProcessor(exporter, schedule_delay_millis=1000, max_export_batch_size=32)
        )
    )
    return _provider


@contextmanager
def bench_turn(headers: Mapping[str, str], *, from_bench: bool) -> Iterator[None]:
    """Run one request's agent work in the bench's trace. `from_bench` is the route's
    own answer to "did this request authenticate as the bench?"; when it is False, or
    the request has no X-Veris-Traceparent, nothing is recorded. `headers` must look
    names up case-insensitively, as Starlette, Flask and Django request headers do."""
    value = headers.get(HEADER) if _provider is not None and from_bench else None
    ctx = TraceContextTextMapPropagator().extract({"traceparent": value}) if value else None
    parent = trace.get_current_span(ctx).get_span_context() if ctx is not None else None
    if parent is None or not parent.is_valid:
        yield
        return
    trace_id = parent.trace_id
    with _lock:
        _running[trace_id] = _running.get(trace_id, 0) + 1
    # Attached, not passed as `context=`: the turn span then becomes current on top of
    # the marked context, so every span started inside the turn carries the marker.
    token = otel_context.attach(otel_context.set_value(_TURN, trace_id, ctx))
    try:
        with _provider.get_tracer(__name__).start_as_current_span(
            TURN_SPAN, record_exception=False, set_status_on_exception=False
        ):
            yield
    finally:
        otel_context.detach(token)
        with _lock:
            _running[trace_id] -= 1
            if not _running[trace_id]:
                del _running[trace_id]


def flush(timeout_millis: int = 2000) -> None:
    """Send what is buffered now. Call it after a bench turn, before the response
    returns, on a host that stops the process's CPU between requests (serverless). It
    blocks for up to `timeout_millis`: from async code, run it in a thread."""
    if _provider is not None:
        _provider.force_flush(timeout_millis)
