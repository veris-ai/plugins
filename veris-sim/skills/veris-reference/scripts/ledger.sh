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
#   ledger.sh init          --task <id>
#   ledger.sh check         --task <id>
#   ledger.sh --against-diff --task <id> [--base <ref>]
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

usage() {
  cat >&2 <<EOF
$ME: the measurement ledger.

  $ME init           --task <id>
  $ME check          --task <id>
  $ME --against-diff --task <id> [--base <ref>]

--task may be omitted when VERIS_TASK_ID is set.
--base defaults to the base_commit recorded by record.sh.
The changed set is the diff against the base, plus every declared file whose
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

case "${1:-}" in
  init|check)      MODE="$1"; shift ;;
  --against-diff)  MODE='against-diff'; shift ;;
  -h|--help|'')    usage ;;
  *)               die "unknown mode '${1}'. Modes: init, check, --against-diff." ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --task) [ $# -ge 2 ] || die "--task needs a value"; TASK="$2"; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a value"; BASE="$2"; shift 2 ;;
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

One JSON object per line. Required on every row:

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
  counterfactual required if and only if NON_LOAD_BEARING
  reviewer       optional

Snapshots go in $SNAPDIR/ and are what survives delete_sandbox.
EOF
  exit 0
fi

# --------------------------------------------------------------------- check

[ -f "$LEDGER" ] || die "$LEDGER does not exist; run '$ME init --task $TASK' first"

if [ "$MODE" = against-diff ]; then
  RECORDED=''
  if [ -z "$BASE" ] && [ -f "$RECORD" ]; then
    BASE="$(jq -r '.base_commit // empty' "$RECORD" 2>/dev/null || true)"
    [ -n "$BASE" ] && RECORDED=1
  fi
  [ -n "$BASE" ] || die "no base commit: run 'record.sh base' when the task starts, or pass --base <full-sha>"
  git rev-parse --verify --quiet "$BASE" >/dev/null || die "base '$BASE' is not a commit in this repository"

  # A base the change picks at gate time is not a base. `HEAD` is the case that
  # bites: run the gate before committing and it names the starting commit; run
  # it after and the changed set is empty, so every ENCODED row fails for a
  # reason that has nothing to do with the measurements. Pin it when the task
  # starts, before the first edit.
  if [ -z "$RECORDED" ]; then
    case "$BASE" in
      *[!0-9a-f]*) PINNED='' ;;
      *) [ "${#BASE}" -eq 40 ] && PINNED=1 || PINNED='' ;;
    esac
    [ -n "$PINNED" ] || die "base '$BASE' is a moving reference and no $RECORD exists. Run 'record.sh base' when the task starts, then call this without --base; or pass the full 40-character sha the task began at."
  fi
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

  counterfactual="$(get '.counterfactual')"
  if [ "$disposition" = NON_LOAD_BEARING ] && [ -z "$counterfactual" ]; then
    fail "$id: NON_LOAD_BEARING needs a counterfactual — the different value this measurement could have taken without changing the promised outcome"
  fi
  if [ "$disposition" != NON_LOAD_BEARING ] && [ -n "$counterfactual" ]; then
    warn "$id: counterfactual is only meaningful on NON_LOAD_BEARING"
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
