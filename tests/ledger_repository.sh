#!/usr/bin/env sh
# ledger.sh check holds REPOSITORY rows to proof.md: state read back, never a
# call-shape assertion against a stub.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LED="$HERE/veris/skills/veris-reference/scripts/ledger.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
mkdir -p .veris/tasks/t/snapshots

row() { # row <probe> <evidence_ref json>
  printf '{"id":"r1","claim":"refund carries the requested amount","layer":"REPOSITORY","probe":"%s","observed":"2 passed","evidence_ref":%s,"decision":"pass amount when given","code_ref":{"file":"refunds/service.py","symbol":"refund"},"disposition":"ENCODED"}\n' \
    "$1" "$2" > .veris/tasks/t/measurements.jsonl
}
fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}
nonzero() { [ "$1" -ne 0 ] && echo 1 || echo 0; }

# 1. A mock call-shape assertion is refused, and the refusal says why.
row "uv run pytest tests/test_unit.py -q" \
  '{"test":"tests/test_unit.py::test_partial","state_read_back":"Mock call arguments were payment_intent and amount=1500"}'
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "mock evidence: check fails" 1 "$(nonzero $rc)"
check "mock evidence: names the stub" 1 "$(printf '%s' "$out" | grep -ci 'stub')"

# 2. No state read back is refused.
row "veris run -- uv run pytest -q" '{"test":"tests/test_refunds.py::test_partial_refund"}'
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "no state_read_back: check fails" 1 "$(nonzero $rc)"
check "no state_read_back: names the field" 1 "$(printf '%s' "$out" | grep -c 'state_read_back')"

# 3. A real read-back passes (guard).
row "veris run --patch-bundled-cas --require-service stripe -- uv run pytest -q" \
  '{"test":"tests/test_refunds.py::test_partial_refund","state_read_back":"refund.amount read back as 1500; veris sandbox data get stripe refunds shows amount=1500"}'
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "real read-back: check passes" 0 "$rc"

if [ "$fails" -eq 0 ]; then echo "ledger_repository: all passed"; else echo "ledger_repository: $fails failed"; exit 1; fi
