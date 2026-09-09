#!/usr/bin/env sh
# The measurement ledger: structure, locators, and the diff.
#
# What this checks, exactly: that every measurement is recorded in a permitted
# shape, that its evidence is still readable after the sandbox is gone, and that
# every measurement the change claims to honour points at a file the change
# actually touched.
#
# What this does NOT check, and cannot: whether the code truly obeys a
# measurement, or whether a claim's sentence quietly asserts something about a
# second layer. Both are semantic judgements. They belong to the behavioural
# tests the invariants require, and to a reviewer. A script that pattern-matched
# claim text here would manufacture exactly the false confidence the ledger
# exists to remove.
#
# So this script cannot close the reconciliation. What it can do is refuse a
# ledger that never attempted one: an ENCODED row carries the `falsifier` -- the
# input under which the shipped code would violate the measurement, or the state
# that makes the escape hatch unreachable -- and the `run_ref` of the run that
# drove it through the shipping path. Both are text this script only checks the
# presence of. Driving the falsifier is the step that decides the row.
#
#   ledger.sh init          --task <id>
#   ledger.sh add           --task <id> [--row <json> | --row @<file> | --row -]
#   ledger.sh check         --task <id>
#   ledger.sh --against-diff --task <id>
#
# Exit: 0 ok · 1 usage or environment error · 2 a gate failure.
set -u

ME="ledger.sh"
# Three layers, not five. A transport claim is the receipt, which a gate already
# demands, and no study in the campaign has had real-vendor access to record.
# Add a layer back when a task needs one, rather than carrying it speculatively.
LAYERS='REPOSITORY TWIN VENDOR_CONTRACT'
OBSERVED_LAYERS='TWIN'
DISPOSITIONS='ENCODED NON_LOAD_BEARING CONTRADICTED UNRESOLVED'
ROW_TYPES='MEASUREMENT DEFAULT_PATH'

usage() {
  cat >&2 <<EOF
$ME: the measurement ledger.

  $ME init           --task <id>
  $ME add            --task <id> [--row <json> | --row @<file> | --row -]
  $ME check          --task <id>
  $ME --against-diff --task <id>

--task may be omitted when VERIS_TASK_ID is set.
'add' stamps the row with the time it was written and appends it. Write each row
when you take the measurement; a ledger transcribed at the end records the story
you tell about the task, not the task.
The base comes from the record.json record.sh pinned before the first edit, and
from nowhere else: there is no --base. A base the change names at gate time is
chosen by the thing being measured.
The changed set is the diff against that base, plus every declared file whose
digest has moved since record.sh pinned it.
EOF
  exit 1
}

die()  { printf '%s: %s\n' "$ME" "$1" >&2; exit 1; }
note() { printf '%s: %s\n' "$ME" "$1"; }

FAILURES=0
WARNINGS=0
fail() { printf '%s: FAIL %s\n' "$ME" "$1" >&2; FAILURES=$((FAILURES + 1)); }
warn() { printf '%s: warn %s\n' "$ME" "$1" >&2; WARNINGS=$((WARNINGS + 1)); }

# sha256sum on GNU, shasum -a 256 on macOS. Nothing else is assumed.
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "neither sha256sum nor shasum is on PATH"
  fi
}

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else die "neither sha256sum nor shasum is on PATH"
  fi
}

contains() { # contains <needle> <space-separated haystack>
  for _c in $2; do [ "$_c" = "$1" ] && return 0; done
  return 1
}

# Two passes so the specific token shapes stay case-sensitive (they are, in
# reality) while the generic "<keyword> = <long value>" clause is not.
SECRET_SHAPES='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|sk_live_[A-Za-z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20}\.[A-Za-z0-9_-]{20}'
SECRET_ASSIGN='(api[_-]?key|secret|passwd|password|bearer|private[_-]?key)"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9_+/-]{24}'

secret_scan() { # secret_scan <label> <file>
  [ -f "$2" ] || return 0
  if grep -qE "$SECRET_SHAPES" "$2" 2>/dev/null ||
     grep -qiE "$SECRET_ASSIGN" "$2" 2>/dev/null; then
    fail "$1 matches a credential pattern. A ledger carries identifiers, paths and redacted excerpts — never key material."
  fi
}

# ---------------------------------------------------------------- arguments

MODE=''
TASK="${VERIS_TASK_ID:-}"
BASE=''
ROWARG=''

case "${1:-}" in
  init|add|check)  MODE="$1"; shift ;;
  --against-diff)  MODE='against-diff'; shift ;;
  -h|--help|'')    usage ;;
  *)               die "unknown mode '${1}'. Modes: init, add, check, --against-diff." ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --task) [ $# -ge 2 ] || die "--task needs a value"; TASK="$2"; shift 2 ;;
    --row)  [ $# -ge 2 ] || die "--row needs a value";  ROWARG="$2"; shift 2 ;;
    # A base the change picks at gate time is not a base: run 2 of the
    # medusa-capture study passed `--base HEAD` in place of a record.json, and
    # every ENCODED row was then measured against a diff the fix itself framed.
    # The flag is gone rather than deprecated, so its absence is an error the
    # agent reads instead of a silent substitution.
    --base) die "--base is not accepted. The base is the base_commit in .veris/tasks/<id>/record.json, pinned by 'record.sh base' before the first edit. Pin it there." ;;
    *)      die "unexpected argument '$1'" ;;
  esac
done

[ -n "$TASK" ] || die "no task id. Pass --task <id>, or set VERIS_TASK_ID."
case "$TASK" in
  */*|..*|'') die "task id '$TASK' must be a single path segment" ;;
esac

command -v jq >/dev/null 2>&1 || die "jq is not on PATH; every row is JSON"

DIR=".veris/tasks/$TASK"
LEDGER="$DIR/measurements.jsonl"
SNAPDIR="$DIR/snapshots"
RECORD="$DIR/record.json"

# ---------------------------------------------------------------------- init

if [ "$MODE" = init ]; then
  mkdir -p "$SNAPDIR" || die "cannot create $SNAPDIR"
  [ -f "$LEDGER" ] || : > "$LEDGER"
  cat <<EOF
$ME: $LEDGER ready.

One JSON object per line, appended with '$ME add --task $TASK --row <json>' at
the moment the measurement is taken. Required on every row:

  id             stable within this task
  claim          one layer's assertion
  layer          $LAYERS
  probe          the command or call
  observed       the result, quoted
  evidence_ref   TWIN: ids plus snapshot (a path under snapshots/) and
                   snapshot_sha256
                 VENDOR_CONTRACT: url and quote, or {"silent": true}
                 REPOSITORY: test and state_read_back
  decision       the code or design decision it bears on
  code_ref       {file, symbol or decision_id}
  disposition    $DISPOSITIONS
  written_at     RFC 3339 UTC; 'add' stamps it, do not write it by hand
  row_type       $ROW_TYPES (default MEASUREMENT)
  counterfactual required if and only if NON_LOAD_BEARING
  falsifier      required on ENCODED: the concrete input or state under which
                   the shipped code would violate this measurement, or why the
                   escape hatch it names is unreachable
  run_ref        required on ENCODED and on DEFAULT_PATH: the run that drove
                   that falsifier through the shipping path -- a receipt path,
                   a snapshot path, or a trace id read back afterwards
  reviewer       optional

Exactly one DEFAULT_PATH row is required before the gate closes: the call the
task names, made by a caller that changed nothing, driven twice through the
changed code, with what the twin stored counted. It carries in addition:

  caller_unchanged  true, and true only if no caller was edited to reach it
  observed          the counts from both drives

Snapshots go in $SNAPDIR/ and are what survives the sandbox.
EOF
  exit 0
fi

# ----------------------------------------------------------------------- add

if [ "$MODE" = add ]; then
  [ -f "$LEDGER" ] || die "$LEDGER does not exist; run '$ME init --task $TASK' first"
  [ -n "$ROWARG" ] || die "--row needs the row: inline JSON, @<file>, or - for stdin"
  case "$ROWARG" in
    -)  ROWJSON="$(cat)" ;;
    @*) f="${ROWARG#@}"; [ -f "$f" ] || die "row file '$f' does not exist"; ROWJSON="$(cat "$f")" ;;
    *)  ROWJSON="$ROWARG" ;;
  esac
  printf '%s\n' "$ROWJSON" | jq -e 'type == "object"' >/dev/null 2>&1 ||
    die "the row is not a JSON object"
  printf '%s\n' "$ROWJSON" | jq -e '.written_at == null' >/dev/null 2>&1 ||
    die "written_at is stamped here, not written by hand: drop it from the row"
  # Seconds, UTC. Two rows a second apart are two measurements; two rows in the
  # same second, three times over, is a ledger transcribed in one sitting, and
  # --against-diff says so.
  STAMPED="$(printf '%s\n' "$ROWJSON" |
    jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '. + {written_at: $at}')" ||
    die "cannot stamp the row"
  printf '%s\n' "$STAMPED" >> "$LEDGER" || die "cannot append to $LEDGER"
  note "row $(printf '%s\n' "$STAMPED" | jq -r '.id // "?"') appended at $(printf '%s\n' "$STAMPED" | jq -r .written_at)."
  exit 0
fi

# --------------------------------------------------------------------- check

[ -f "$LEDGER" ] || die "$LEDGER does not exist; run '$ME init --task $TASK' first"

if [ "$MODE" = against-diff ]; then
  # The record is the only source of the base. Without it there is nothing here
  # to measure the diff against that the diff did not choose, so the gate
  # refuses rather than accepting a substitute.
  [ -f "$RECORD" ] ||
    die "no $RECORD: this gate has no base it did not get from the task's own start. Run 'record.sh base --task $TASK --paths <the files the diagnosis implicates>' before the first edit, and re-run the task from there if that moment has passed."
  BASE="$(jq -r '.base_commit // empty' "$RECORD" 2>/dev/null || true)"
  [ -n "$BASE" ] || die "$RECORD has no base_commit. Re-run 'record.sh base --task $TASK'."
  git rev-parse --verify --quiet "$BASE" >/dev/null || die "base '$BASE' is not a commit in this repository"
  CHANGED="$(git diff --name-only "$BASE" -- 2>/dev/null; git diff --name-only --cached "$BASE" -- 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)"

  # git alone is not the change. When the defect lived only in the worktree, the
  # fix restores the committed bytes and the diff against the base is empty for
  # the very file the task edited — so every ENCODED row naming it would fail
  # for a reason that has nothing to do with the measurements. record.sh pinned
  # each declared file's digest at `base`; a file whose digest has moved since
  # was changed by this task, whatever git says. This is the set record.sh
  # refuses a drifted red run on.
  if [ -f "$RECORD" ]; then
    DRIFTED="$(jq -r '.source_digests | to_entries[] | "\(.value) \(.key)"' "$RECORD" 2>/dev/null |
      while IFS=' ' read -r was f; do
        [ -n "$f" ] || continue
        if [ -f "$f" ]; then now="$(sha256 "$f")"; else now=''; fi
        [ "$now" = "$was" ] || printf '%s\n' "$f"
      done)"
    if [ -n "$DRIFTED" ]; then
      CHANGED="$CHANGED
$DRIFTED"
    fi
  fi
fi

ROW=0
DEFAULT_PATH_ROWS=0
STAMPS=''
secret_scan "$LEDGER" "$LEDGER"

# A file redirect, not a pipe: the failure counter has to survive the loop.
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  ROW=$((ROW + 1))

  if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
    fail "row $ROW is not valid JSON"
    continue
  fi

  get() { printf '%s\n' "$line" | jq -r "$1 // empty" 2>/dev/null; }

  id="$(get '.id')"
  [ -n "$id" ] || { fail "row $ROW has no id"; id="row $ROW"; }

  for field in claim probe observed decision; do
    [ -n "$(get ".$field")" ] || fail "$id: $field is missing or empty"
  done

  # layer: exactly one, and permitted. Whether the *claim* is genuinely about
  # one layer is a grader's call, not this script's.
  if [ "$(printf '%s\n' "$line" | jq -r '.layer | type')" != string ]; then
    fail "$id: layer must be a single string, one of: $LAYERS"
    layer=''
  else
    layer="$(get '.layer')"
    contains "$layer" "$LAYERS" || fail "$id: layer '$layer' is not one of: $LAYERS"
  fi

  disposition="$(get '.disposition')"
  contains "$disposition" "$DISPOSITIONS" ||
    fail "$id: disposition '$disposition' is not one of: $DISPOSITIONS"

  # When the row was written. A ledger assembled at the end is a summary of the
  # task, and a summary is exactly the artifact that cannot contradict the code.
  written_at="$(get '.written_at')"
  if [ -z "$written_at" ]; then
    fail "$id: written_at is missing — append rows with '$ME add --task $TASK --row <json>' as you measure, which stamps it"
  else
    STAMPS="$STAMPS
$written_at"
  fi

  row_type="$(get '.row_type')"
  [ -n "$row_type" ] || row_type=MEASUREMENT
  contains "$row_type" "$ROW_TYPES" ||
    fail "$id: row_type '$row_type' is not one of: $ROW_TYPES"

  if [ "$row_type" = DEFAULT_PATH ]; then
    DEFAULT_PATH_ROWS=$((DEFAULT_PATH_ROWS + 1))
    [ "$(get '.caller_unchanged')" = true ] ||
      fail "$id: DEFAULT_PATH needs caller_unchanged: true — the point of the row is the call as an unchanged caller makes it. A caller edited to reach the new behaviour measures the edit."
    [ -n "$(get '.run_ref')" ] ||
      fail "$id: DEFAULT_PATH needs run_ref — the run that drove that call twice through the changed code"
  fi

  counterfactual="$(get '.counterfactual')"
  if [ "$disposition" = NON_LOAD_BEARING ] && [ -z "$counterfactual" ]; then
    fail "$id: NON_LOAD_BEARING needs a counterfactual — the different value this measurement could have taken without changing the promised outcome"
  fi
  if [ "$disposition" != NON_LOAD_BEARING ] && [ -n "$counterfactual" ]; then
    warn "$id: counterfactual is only meaningful on NON_LOAD_BEARING"
  fi

  # ENCODED is the disposition that has been wrong every time. Three runs marked
  # a row ENCODED whose own decision text rests on a code path the shipped code
  # can never reach. This script cannot read the code; it can refuse a row that
  # never named what would break it, and never drove that.
  if [ "$disposition" = ENCODED ]; then
    [ -n "$(get '.falsifier')" ] ||
      fail "$id: ENCODED needs a falsifier — the concrete input or state under which the shipped code would violate this measurement, or why the escape hatch it names is unreachable. Writing it is how you find out the row is CONTRADICTED."
    [ -n "$(get '.run_ref')" ] ||
      fail "$id: ENCODED needs run_ref — the run that drove that falsifier through the shipping path under 'veris run', with the twin read back afterwards. A falsifier written and not driven is a sentence."
  fi

  [ -n "$(get '.code_ref.file')" ] || fail "$id: code_ref.file is missing"
  if [ -z "$(get '.code_ref.symbol')" ] && [ -z "$(get '.code_ref.decision_id')" ]; then
    fail "$id: code_ref needs a symbol or a decision_id — a line number alone moves under the next edit"
  fi

  # Evidence that outlives the sandbox.
  if contains "$layer" "$OBSERVED_LAYERS"; then
    snap="$(get '.evidence_ref.snapshot')"
    snapsha="$(get '.evidence_ref.snapshot_sha256')"
    if [ -z "$snap" ] || [ -z "$snapsha" ]; then
      fail "$id: $layer needs evidence_ref.snapshot and .snapshot_sha256 — ids stop resolving the moment the sandbox is deleted"
    else
      case "$snap" in /*|*..*) fail "$id: snapshot path '$snap' must be relative to $DIR" ;; esac
      snappath="$DIR/$snap"
      if [ ! -f "$snappath" ]; then
        fail "$id: snapshot $snappath is missing"
      else
        actual="$(sha256 "$snappath")"
        [ "$actual" = "$snapsha" ] ||
          fail "$id: snapshot digest mismatch — recorded $snapsha, file is $actual"
        secret_scan "$id snapshot $snap" "$snappath"
      fi
    fi
  elif [ "$layer" = VENDOR_CONTRACT ]; then
    if [ "$(get '.evidence_ref.silent')" != true ] && [ -z "$(get '.evidence_ref.url')" ]; then
      fail "$id: VENDOR_CONTRACT needs evidence_ref.url, or {\"silent\": true} when the documentation says nothing"
    fi
  elif [ "$layer" = REPOSITORY ]; then
    [ -n "$(get '.evidence_ref.test')" ] ||
      fail "$id: REPOSITORY needs evidence_ref.test — the test that drove the code"
    [ -n "$(get '.evidence_ref.state_read_back')" ] ||
      fail "$id: REPOSITORY needs evidence_ref.state_read_back — what the code left behind, read back"
    # proof.md: a REPOSITORY claim is never closed by a call-shape assertion
    # against a stub. The words that describe one are the honest tell.
    if printf '%s\n' "$(get '.evidence_ref.state_read_back') $(get '.evidence_ref.test') $(get '.probe')" |
       grep -qiE 'mock|stub|assert_called|monkeypatch|MagicMock|patch\('; then
      fail "$id: REPOSITORY evidence is a call-shape assertion against a stub — proof.md: mocks are branch coverage, never the evidence a claim closes on"
    fi
  fi

  # --against-diff only.
  if [ "$MODE" = against-diff ]; then
    case "$disposition" in
      CONTRADICTED)
        fail "$id: CONTRADICTED — the diff does something this measurement says is wrong. Change the code, not the report." ;;
      UNRESOLVED)
        fail "$id: UNRESOLVED — this measurement was never settled. Settle it, or report it and stop." ;;
      ENCODED)
        f="$(get '.code_ref.file')"
        if printf '%s\n' "$CHANGED" | grep -qxF "$f"; then
          sym="$(get '.code_ref.symbol')"
          # Context, not -U0. A function whose body changed but whose signature
          # line did not carries its own name only on a context line, so -U0
          # reports it missing and the honest repair looks like editing the row.
          # Empty hunks with the file in the changed set means the edit is
          # worktree-only against the base: git has nothing to search, so this
          # check has nothing to say.
          hunks=''
          [ -n "$sym" ] && hunks="$(git diff -U10 "$BASE" -- "$f" 2>/dev/null)"
          if [ -n "$hunks" ] && ! printf '%s\n' "$hunks" | grep -qF "$sym"; then
            warn "$id: '$sym' does not appear in the changed hunks of $f (renamed? moved?)"
          fi
        else
          fail "$id: ENCODED names $f, which the change does not touch"
        fi ;;
    esac
  fi
done < "$LEDGER"

[ "$ROW" -gt 0 ] || warn "the ledger is empty"

# One timestamp across the whole ledger is a ledger written once, at the end.
# Run 2 of the medusa-capture study wrote seven rows in a single file write
# fourteen minutes after the last source edit; every row passed. Measurements
# taken minutes apart do not share a second.
DISTINCT="$(printf '%s\n' "$STAMPS" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')"
if [ "$ROW" -ge 3 ] && [ "$DISTINCT" = 1 ]; then
  fail "all $ROW rows share one written_at. A ledger written in one sitting records the account of the task, not the task. Append each row with '$ME add' when you take the measurement."
elif [ "$ROW" -ge 2 ] && [ "$DISTINCT" = 1 ]; then
  warn "both rows share one written_at — append each row when you take it, not at the end"
fi

if [ "$MODE" = against-diff ] && [ "$DEFAULT_PATH_ROWS" -eq 0 ]; then
  fail "no DEFAULT_PATH row. Name the call the task describes, make it as a caller that changed nothing makes it, drive it twice through the changed code under 'veris run', and count what the twin stored. A guard that does not engage there is not done, and that finding does not go under limitations."
fi

# ------------------------------------------------------------------- verdict

if [ "$MODE" = against-diff ] && [ "$FAILURES" -eq 0 ]; then
  d_ledger="$(sha256 "$LEDGER")"
  d_snaps='none'
  if [ -d "$SNAPDIR" ] && [ -n "$(ls -A "$SNAPDIR" 2>/dev/null)" ]; then
    d_snaps="$(for f in "$SNAPDIR"/*; do [ -f "$f" ] && sha256 "$f"; done | sort | sha256_stdin)"
  fi
  cat <<EOF

Ledger digest (for the change description)
  rows        $ROW
  base        $BASE
  ledger      sha256:$d_ledger
  snapshots   sha256:$d_snaps
EOF
fi

if [ "$FAILURES" -gt 0 ]; then
  printf '%s: %d failure(s), %d warning(s) across %d row(s).\n' "$ME" "$FAILURES" "$WARNINGS" "$ROW" >&2
  exit 2
fi
note "$ROW row(s) ok, $WARNINGS warning(s)."
exit 0
