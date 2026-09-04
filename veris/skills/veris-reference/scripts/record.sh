#!/usr/bin/env sh
# The source-state and execution record.
#
# This is a record, not a proof. It cannot show that a fix was never stashed and
# reconstructed, and a build that ran after a recorded source state is not the
# same as a build produced from it. What it does: pin the source you declared
# before the failing run, refuse a run whose source has moved since, refuse a run
# whose build output is older than that source, and write down what each run
# actually did — so a reader can check the order instead of trusting a sentence.
#
#   record.sh base  --task <id> [--paths <p>...]
#   record.sh red   --task <id> --expect <mode> -- <command...>
#   record.sh green --task <id> --expect <mode> -- <command...>
#   record.sh block --task <id>
#
# Everything after -- is run exactly as given, one argv element per word, so
# quotes and parentheses reach the program. Nothing re-parses it: a pipe, a
# redirect or a $VAR wants an explicit `-- sh -c '...'`.
#
# --expect, at red — the expectation is MET when:
#   nonzero            the command exits non-zero
#   assertion=<text>   <text> appears in the command's output
#   predicate=<cmd>    <cmd> EXITS 0 — the predicate confirms the wrong state.
#                      Predicates are written to detect the defect, so success
#                      means the defect reproduced.
#   baseline           always (a build task often has no red at all)
#
# At green every expectation inverts: the test passes, the failure string is
# gone, the predicate no longer finds the defect.
#
# Exit: 0 ok · 1 usage or environment error · 2 a refusal or an unmet expectation.
set -u

ME="record.sh"

usage() {
  cat >&2 <<EOF
$ME: the source-state and execution record.

  $ME base  --task <id> [--paths <path>...]
  $ME red   --task <id> --expect <mode> -- <command...>
  $ME green --task <id> --expect <mode> -- <command...>
  $ME block --task <id>

--expect: nonzero | assertion=<text> | predicate=<cmd> | baseline
The command after -- runs as given; shell features need -- sh -c '...'.
--task may be omitted when VERIS_TASK_ID is set.
EOF
  exit 1
}

die()  { printf '%s: %s\n' "$ME" "$1" >&2; exit 1; }
note() { printf '%s: %s\n' "$ME" "$1"; }
stop() { printf '%s: REFUSED %s\n' "$ME" "$1" >&2; exit 2; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "neither sha256sum nor shasum is on PATH"
  fi
}

json_str() { printf '%s' "$1" | jq -Rs .; }

# ---------------------------------------------------------------- arguments

MODE="${1:-}"
case "$MODE" in
  base|red|green|block) shift ;;
  -h|--help|'')         usage ;;
  *)                    die "unknown mode '$MODE'. Modes: base, red, green, block." ;;
esac

TASK="${VERIS_TASK_ID:-}"
EXPECT=''
PATHS=''
CMD=''

while [ $# -gt 0 ]; do
  case "$1" in
    --task)   [ $# -ge 2 ] || die "--task needs a value";   TASK="$2"; shift 2 ;;
    --expect) [ $# -ge 2 ] || die "--expect needs a value"; EXPECT="$2"; shift 2 ;;
    --paths)
      shift
      while [ $# -gt 0 ]; do
        case "$1" in --*|--) break ;; esac
        PATHS="$PATHS
$1"; shift
      done ;;
    --) shift; CMD="$*"; break ;;
    *)  die "unexpected argument '$1'" ;;
  esac
done
# From here on "$@" is the command to run; $CMD is its display form only.

[ -n "$TASK" ] || die "no task id. Pass --task <id>, or set VERIS_TASK_ID."
case "$TASK" in */*|..*|'') die "task id '$TASK' must be a single path segment" ;; esac
command -v jq >/dev/null 2>&1 || die "jq is not on PATH"
git rev-parse --git-dir >/dev/null 2>&1 || die "not inside a git repository"

DIR=".veris/tasks/$TASK"
RECORD="$DIR/record.json"
SETUP=".veris/setup.json"

setup_get() { [ -f "$SETUP" ] && jq -r "$1 // empty" "$SETUP" 2>/dev/null || true; }
rec_get()   { [ -f "$RECORD" ] && jq -r "$1 // empty" "$RECORD" 2>/dev/null || true; }

# Every file under the declared paths, one per line, .git and .veris excluded.
list_files() { # list_files <newline-separated paths>
  printf '%s\n' "$1" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -f "$p" ]; then printf '%s\n' "$p"
    elif [ -d "$p" ]; then find "$p" -type f ! -path '*/.git/*' ! -path '*/.veris/*' 2>/dev/null
    fi
  done | sort -u
}

digest_paths() { # digest_paths <newline-separated paths> -> {"file": "sha", ...}
  list_files "$1" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    printf '%s %s\n' "$f" "$(sha256 "$f")"
  done | jq -Rn '[inputs | split(" ") | {(.[0]): .[1]}] | add // {}'
}

# ---------------------------------------------------------------------- base

if [ "$MODE" = base ]; then
  mkdir -p "$DIR" || die "cannot create $DIR"

  flags=''
  if [ -z "$PATHS" ]; then
    roots="$(setup_get '.source_roots[]?')"
    if [ -n "$roots" ]; then
      PATHS="$roots"
      flags="$flags PATHS_UNNARROWED"
      note "no --paths: falling back to source_roots from $SETUP, which pins the whole source tree. Pass --paths with the files this task changes."
    else
      die "no --paths and no source_roots in $SETUP. Name the files this task changes."
    fi
  else
    roots="$(setup_get '.source_roots[]?')"
    if [ -n "$roots" ]; then
      # Does the path fall UNDER a declared root? The roots carry globs
      # (packages/modules/*/src), so this is a glob match of the path against
      # each root, not a string compare of one against the other.
      printf '%s\n' "$PATHS" | while IFS= read -r p; do
        [ -n "$p" ] || continue
        _inside=''
        for _r in $roots; do
          # shellcheck disable=SC2254  # $_r is a pattern on purpose
          case "$p" in
            $_r|$_r/*) _inside=1; break ;;
          esac
        done
        [ -n "$_inside" ] ||
          printf '%s: note %s is outside the recorded source_roots — allowed; a diagnosis may implicate a file setup did not anticipate.\n' "$ME" "$p" >&2
      done
    fi
  fi

  build_command="$(setup_get '.build_command')"
  build_outputs="$(setup_get '.build_outputs[]?')"
  [ -n "$build_command" ] || flags="$flags BUILD_PROVENANCE_UNKNOWN"

  src_json="$(digest_paths "$PATHS")"
  out_json='{}'
  [ -n "$build_outputs" ] && out_json="$(digest_paths "$build_outputs")"

  count="$(printf '%s' "$src_json" | jq 'length')"
  [ "$count" -gt 0 ] || die "the declared paths matched no files"
  [ "$count" -le 2000 ] || note "$count files declared — narrow --paths to what this task changes"

  jq -n \
    --arg base "$(git rev-parse HEAD)" \
    --arg branch "$(git rev-parse --abbrev-ref HEAD)" \
    --arg status "$(git status --porcelain)" \
    --arg bc "$build_command" \
    --arg flags "$flags" \
    --argjson paths "$(printf '%s\n' "$PATHS" | jq -Rn '[inputs | select(length>0)]')" \
    --argjson src "$src_json" \
    --argjson out "$out_json" \
    --argjson outpaths "$(printf '%s\n' "$build_outputs" | jq -Rn '[inputs | select(length>0)]')" \
    '{task_dir: "'"$DIR"'", base_commit: $base, branch: $branch,
      worktree_at_base: $status, declared_paths: $paths,
      source_digests: $src, build_command: $bc,
      build_output_paths: $outpaths, build_output_digests: $out,
      flags: ($flags | split(" ") | map(select(length>0))),
      runs: []}' > "$RECORD" || die "cannot write $RECORD"

  note "base $(git rev-parse --short HEAD), $count file(s) pinned.${flags:+ flags:$flags}"
  [ -n "$(git status --porcelain)" ] &&
    note "pre-existing worktree changes recorded, not forbidden."
  exit 0
fi

# ----------------------------------------------------------------- red/green

if [ "$MODE" = block ]; then
  [ -f "$RECORD" ] || die "$RECORD does not exist"
  jq -r '
    "Source-state and execution record (a record, not a proof)",
    "  base commit   \(.base_commit) on \(.branch)",
    "  declared      \(.declared_paths | join(", "))",
    "  build         \(if .build_command == "" then "unknown — BUILD_PROVENANCE_UNKNOWN" else .build_command end)",
    (if (.flags | length) > 0 then "  flags         \(.flags | join(", "))" else empty end),
    (if (.worktree_at_base | length) > 0 then "  at base       the worktree already carried changes (recorded)" else empty end),
    "",
    (.runs[] | "  \(.phase | ascii_upcase)  \(.verdict)\n    command     \(.command)\n    expect      \(.expect)\n    exit        \(.exit)\(if .first_edit_seen then "\n    note        production source had changed before this run" else "" end)")
  ' "$RECORD"
  exit 0
fi

[ -f "$RECORD" ] || die "$RECORD does not exist; run '$ME base --task $TASK' first"
[ $# -gt 0 ] || die "no command. Put it after --."
[ -n "$EXPECT" ] || die "no --expect. One of: nonzero, assertion=<text>, predicate=<cmd>, baseline."

case "$EXPECT" in
  nonzero|baseline|assertion=*|predicate=*) ;;
  *) die "unknown --expect '$EXPECT'. One of: nonzero, assertion=<text>, predicate=<cmd>, baseline." ;;
esac

PATHS="$(jq -r '.declared_paths[]' "$RECORD")"
now_src="$(digest_paths "$PATHS")"
base_src="$(jq -c '.source_digests' "$RECORD")"
drifted="$(jq -rn --argjson a "$base_src" --argjson b "$now_src" \
  '[($a|keys[]) as $k | select($a[$k] != ($b[$k] // "")) | $k] + [($b|keys[]) as $k | select($a[$k] == null) | $k] | unique | .[]')"

if [ "$MODE" = red ]; then
  if [ -n "$drifted" ]; then
    printf '%s\n' "$drifted" | sed 's/^/    /' >&2
    stop "the declared production source has changed since 'base'. A red run has to meet the code the failure was reported against — reset these, or re-run 'base' if the change is deliberate and pre-existing."
  fi

  # Stale generated output is how a red passes against a fix that is still on
  # disk: the source was put back, the build was not.
  bc="$(rec_get '.build_command')"
  outs="$(jq -r '.build_output_digests | keys[]?' "$RECORD")"
  if [ -n "$bc" ] && [ -n "$outs" ]; then

    # First, by content, which no clock granularity can defeat. The source is
    # already known unchanged since base — so if the build output has moved,
    # what is on disk was produced from something else.
    base_out="$(jq -c '.build_output_digests' "$RECORD")"
    # Re-digest the paths that were declared, not paths recovered from the file
    # list: a nested output directory would otherwise be scanned incompletely
    # and every unseen file would read as "moved".
    now_out="$(digest_paths "$(jq -r '.build_output_paths[]? // empty' "$RECORD")")"
    moved="$(jq -rn --argjson a "$base_out" --argjson b "$now_out" \
      '[(($a|keys) + ($b|keys) | unique)[] as $k | select(($a[$k] // "") != ($b[$k] // "")) | $k] | .[]' | head -3)"
    if [ -n "$moved" ]; then
      printf '%s\n' "$moved" | sed 's/^/    /' >&2
      stop "the source is unchanged since 'base' but the generated output has moved. The run would execute a build made from something else, and a red that passes for that reason proves nothing. Rebuild first: $bc"
    fi
  fi
  [ -n "$bc" ] || note "no build_command recorded — BUILD_PROVENANCE_UNKNOWN; staleness was not checked."
fi

first_edit_seen=false
[ -n "$drifted" ] && first_edit_seen=true

note "running: $CMD"
OUT="$(mktemp)" || die "cannot create a temporary file"
CODEF="$(mktemp)" || die "cannot create a temporary file"
# POSIX sh has no PIPESTATUS: the command's own exit code goes through a file,
# or `tee` would report success for every failing run. The command is "$@",
# never a re-parsed string: what the caller typed is what runs.
{ "$@" 2>&1; printf '%s\n' "$?" > "$CODEF"; } | tee "$OUT"
CODE="$(cat "$CODEF" 2>/dev/null || echo 1)"
rm -f "$CODEF"

met=false
detail=''
case "$EXPECT" in
  baseline)
    met=true; detail='measurement only' ;;
  nonzero)
    if [ "$MODE" = red ]; then
      [ "$CODE" -ne 0 ] && met=true; detail="exit $CODE"
    else
      [ "$CODE" -eq 0 ] && met=true; detail="exit $CODE"
    fi ;;
  assertion=*)
    text="${EXPECT#assertion=}"
    if grep -qF "$text" "$OUT"; then found=true; else found=false; fi
    if [ "$MODE" = red ]; then
      [ "$found" = true ] && met=true
    else
      [ "$found" = false ] && met=true
    fi
    detail="assertion present: $found" ;;
  predicate=*)
    pcmd="${EXPECT#predicate=}"
    note "predicate: $pcmd"
    sh -c "$pcmd" >/dev/null 2>&1
    PCODE=$?
    # A predicate detects the defect: exit 0 means the wrong state is there.
    if [ "$MODE" = red ]; then
      [ "$PCODE" -eq 0 ] && met=true
    else
      [ "$PCODE" -ne 0 ] && met=true
    fi
    detail="predicate exit $PCODE" ;;
esac

if [ "$met" = true ]; then verdict="$(printf '%s' "$MODE" | tr a-z A-Z)_EXPECTATION_MET"
else verdict="$(printf '%s' "$MODE" | tr a-z A-Z)_EXPECTATION_NOT_MET"; fi

tmp="$(mktemp)" || die "cannot create a temporary file"
jq --arg phase "$MODE" --arg cmd "$CMD" --arg expect "$EXPECT" \
   --arg detail "$detail" --arg verdict "$verdict" \
   --argjson code "$CODE" --argjson fe "$first_edit_seen" \
   '.runs += [{phase: $phase, command: $cmd, expect: $expect, exit: $code,
               detail: $detail, verdict: $verdict, first_edit_seen: $fe}]' \
   "$RECORD" > "$tmp" && mv "$tmp" "$RECORD"
rm -f "$OUT"

if [ "$met" != true ]; then
  if [ "$MODE" = red ]; then
    printf '%s: %s (%s)\n  The failure did not appear. That is the finding, not a step to work around: report what happened instead, or re-frame the reproduction.\n' \
      "$ME" "$verdict" "$detail" >&2
  else
    printf '%s: %s (%s)\n  The change did not close what the red opened.\n' "$ME" "$verdict" "$detail" >&2
  fi
  exit 2
fi

note "$verdict ($detail)"
exit 0
