#!/usr/bin/env sh
# The gates that make the ledger a record of the task rather than an account of
# it. Each case names the run whose failure it closes.
#
#   ENCODED without a falsifier and a run_ref  -- medusa-capture run-1/run-2,
#     quickbooks: measured, written down, marked ENCODED, contradicted by the
#     shipped code. The check cannot read the code; it can refuse a row that
#     never said what would break it.
#   no DEFAULT_PATH row                        -- quickbooks: the correct
#     mechanism shipped behind a parameter no caller passes.
#   --against-diff with no record.json         -- medusa-capture run-2 passed
#     `--base HEAD`, so the base was chosen by the thing being measured.
#   one timestamp across the ledger            -- medusa-capture run-2 wrote
#     seven rows in one file write, fourteen minutes after the last edit.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LED="${LEDGER_SH:-$HERE/veris/skills/veris-reference/scripts/ledger.sh}"
REC="${RECORD_SH:-$HERE/veris/skills/veris-reference/scripts/record.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q && git config user.email t@t && git config user.name t
mkdir -p src .veris && printf 'def capture():\n    return 1\n' > src/app.py
git add -A && git commit -qm init
printf '{"source_roots":["src"],"build_command":"","build_outputs":[]}\n' > .veris/setup.json

LEDGER=.veris/tasks/t/measurements.jsonl
fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

# A well-formed TWIN row, with every field the gate wants, as a jq template the
# cases below subtract from. Nothing here is an escape hatch: each case removes
# exactly one field and asserts the refusal names it.
snapshot() { # snapshot <name>
  mkdir -p .veris/tasks/t/snapshots
  printf 'captures: 1 row, id=cap_1\n' > ".veris/tasks/t/snapshots/$1"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum ".veris/tasks/t/snapshots/$1" | cut -d' ' -f1
  else shasum -a 256 ".veris/tasks/t/snapshots/$1" | cut -d' ' -f1; fi
}
SNAPSHA="$(snapshot green.txt)"

good_row() { # good_row <id> <written_at>   -- cases below del() one field from it
  jq -cn --arg id "$1" --arg at "$2" --arg sha "$SNAPSHA" \
    '{id: $id,
      claim: "a failed capture frees the idempotency key",
      layer: "TWIN",
      probe: "veris sandbox data get stripe captures",
      observed: "one row, id=cap_1",
      evidence_ref: {ids: ["cap_1"], snapshot: "snapshots/green.txt", snapshot_sha256: $sha},
      decision: "rotate the key after a failed capture",
      code_ref: {file: "src/app.py", symbol: "capture"},
      disposition: "ENCODED",
      falsifier: "a capture that fails and is retried reuses the slot the failure freed",
      run_ref: "snapshots/green.txt",
      written_at: $at}'
}

default_row() { # default_row <written_at>
  jq -cn --arg at "$1" \
    '{id: "dp", claim: "the guard engages with no caller change",
      layer: "REPOSITORY", probe: "veris run -- node scripts/capture.js",
      observed: "two drives, one row stored",
      evidence_ref: {test: "scripts/capture.js", state_read_back: "veris sandbox data get stripe captures shows 1 row after both drives"},
      decision: "the guard is on by default",
      code_ref: {file: "src/app.py", symbol: "capture"},
      disposition: "ENCODED",
      falsifier: "a second identical drive would store a second row",
      run_ref: "snapshots/green.txt",
      row_type: "DEFAULT_PATH", caller_unchanged: true,
      written_at: $at}'
}

sh "$LED" init --task t >/dev/null || { echo "FAIL init"; exit 1; }

# 1. ENCODED without a falsifier fails the check, and the refusal names it.
good_row r1 2026-09-09T10:00:00Z | jq -c 'del(.falsifier)' > "$LEDGER"
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "ENCODED without falsifier: check exits 2" 2 "$rc"
check "ENCODED without falsifier: names the field" 1 "$(printf '%s' "$out" | grep -c 'falsifier')"

# 2. ENCODED without a run_ref fails: a falsifier written and not driven is a
#    sentence, which is the artifact the gate exists to refuse.
good_row r1 2026-09-09T10:00:00Z | jq -c 'del(.run_ref)' > "$LEDGER"
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "ENCODED without run_ref: check exits 2" 2 "$rc"
check "ENCODED without run_ref: names the field" 1 "$(printf '%s' "$out" | grep -c 'run_ref')"

# 3. A complete ENCODED row passes the check (guard: the gate refuses omissions,
#    not rows).
good_row r1 2026-09-09T10:00:00Z > "$LEDGER"
rc=0; sh "$LED" check --task t >/dev/null 2>&1 || rc=$?
check "complete ENCODED row: check passes" 0 "$rc"

# 4. --against-diff refuses to run at all without a record.json pinning the
#    base, and --base is not accepted in its place.
out="$(sh "$LED" --against-diff --task t 2>&1)"; rc=$?
check "no record.json: exits 1" 1 "$rc"
check "no record.json: names record.sh base" 1 "$(printf '%s' "$out" | grep -c 'record.sh base')"
out="$(sh "$LED" --against-diff --task t --base HEAD 2>&1)"; rc=$?
check "--base HEAD: refused" 1 "$rc"
check "--base HEAD: says the base comes from record.json" 1 "$(printf '%s' "$out" | grep -c 'record.json')"

# From here the base is pinned the way the skill pins it, before the edit.
sh "$REC" base --task t --paths src >/dev/null 2>&1 || { echo "FAIL record base"; exit 1; }
printf 'def capture(key):\n    return key\n' > src/app.py

# 5. A ledger with no DEFAULT_PATH row fails the diff gate: the mechanism may be
#    correct and still never run for the call the task names.
good_row r1 2026-09-09T10:00:00Z > "$LEDGER"
out="$(sh "$LED" --against-diff --task t 2>&1)"; rc=$?
check "no DEFAULT_PATH row: exits 2" 2 "$rc"
check "no DEFAULT_PATH row: names it" 1 "$(printf '%s' "$out" | grep -c 'DEFAULT_PATH')"

# 6. A DEFAULT_PATH row whose caller was edited to reach the new behaviour is
#    not a default path.
{ good_row r1 2026-09-09T10:00:00Z
  default_row 2026-09-09T10:05:00Z | jq -c '.caller_unchanged = false'; } > "$LEDGER"
out="$(sh "$LED" --against-diff --task t 2>&1)"; rc=$?
check "DEFAULT_PATH caller edited: exits 2" 2 "$rc"
check "DEFAULT_PATH caller edited: names caller_unchanged" 1 "$(printf '%s' "$out" | grep -c 'caller_unchanged')"

# 7. Three rows sharing one written_at is a ledger transcribed at the end.
{ good_row r1 2026-09-09T11:32:39Z
  good_row r2 2026-09-09T11:32:39Z
  default_row 2026-09-09T11:32:39Z; } > "$LEDGER"
out="$(sh "$LED" --against-diff --task t 2>&1)"; rc=$?
check "one timestamp for every row: exits 2" 2 "$rc"
check "one timestamp for every row: says so" 1 "$(printf '%s' "$out" | grep -c 'one written_at')"

# 8. A row with no written_at at all is refused, whatever the mode.
good_row r1 2026-09-09T10:00:00Z | jq -c 'del(.written_at)' > "$LEDGER"
out="$(sh "$LED" check --task t 2>&1)"; rc=$?
check "no written_at: check exits 2" 2 "$rc"
check "no written_at: points at 'add'" 1 "$(printf '%s' "$out" | grep -c 'ledger.sh add')"

# 9. The whole gate passes when the rows were written as they were measured.
{ good_row r1 2026-09-09T10:00:00Z
  good_row r2 2026-09-09T10:14:02Z
  default_row 2026-09-09T10:31:55Z; } > "$LEDGER"
rc=0; sh "$LED" --against-diff --task t >/dev/null 2>&1 || rc=$?
check "complete ledger: --against-diff passes" 0 "$rc"

# 10. 'add' stamps the row itself and refuses one that stamps itself.
: > "$LEDGER"
sh "$LED" add --task t --row "$(good_row r1 2026-09-09T10:00:00Z | jq -c 'del(.written_at)')" >/dev/null 2>&1
check "add: one row appended" 1 "$(wc -l < "$LEDGER" | tr -d ' ')"
check "add: written_at stamped" 1 "$(jq -r 'if .written_at then 1 else 0 end' "$LEDGER")"
out="$(sh "$LED" add --task t --row "$(good_row r2 2026-09-09T10:00:00Z)" 2>&1)"; rc=$?
check "add: a hand-written written_at is refused" 1 "$rc"
check "add: says the stamp is the script's" 1 "$(printf '%s' "$out" | grep -c 'written_at')"

if [ "$fails" -eq 0 ]; then echo "ledger_gates: all passed"; else echo "ledger_gates: $fails failed"; exit 1; fi
