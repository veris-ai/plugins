#!/usr/bin/env sh
# record.sh runs the command after -- as the argv it was given. Nothing
# re-parses it, so quotes and parentheses reach the program, and a command that
# never started cannot earn a verdict.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REC="${RECORD_SH:-$HERE/veris/skills/veris-reference/scripts/record.sh}"  # override to test another copy
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1
git init -q && git config user.email t@t && git config user.name t
mkdir -p src .veris && printf 'x = 1\n' > src/app.py && git add -A && git commit -qm init
printf '{"source_roots":["src"],"build_command":"","build_outputs":[]}\n' > .veris/setup.json
sh "$REC" base --task t --paths src >/dev/null 2>&1 || { echo "FAIL base"; exit 1; }

fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}
runs() { jq '.runs | length' .veris/tasks/t/record.json; }

# 1. Quotes and parentheses reach the program. The asserted text is computed by
#    the program, never typed on the command line, so only real output can match.
out="$(sh "$REC" red --task t --expect 'assertion=got 5000' -- \
  python3 -c 'print("got " + str(5 * 1000)); raise SystemExit(1)' 2>&1)"; rc=$?
check "inline python: exit 0" 0 "$rc"
check "inline python: RED_EXPECTATION_MET" 1 "$(printf '%s' "$out" | grep -c 'RED_EXPECTATION_MET')"
check "inline python: recorded exit is the program's" 1 "$(jq -r '.runs[-1].exit' .veris/tasks/t/record.json)"

# 2. A command that cannot start is an error, not a measurement: exit 1, no run
#    appended, no verdict — even when its arguments carry the asserted text.
before="$(runs)"
out="$(sh "$REC" red --task t --expect 'assertion=expected 1500' -- \
  no-such-binary-veris-test 'expected 1500' 2>&1)"; rc=$?
check "missing binary: exit 1" 1 "$rc"
check "missing binary: no run appended" "$before" "$(runs)"
check "missing binary: no verdict" 0 "$(printf '%s' "$out" | grep -c 'EXPECTATION')"

# 3. Shell features still work when asked for explicitly. (Red before the fix as well:
#    re-parsing turned this into `sh -c "sh -c exit 3"`, whose inner exit sees 3 as $0.)
out="$(sh "$REC" red --task t --expect nonzero -- sh -c 'exit 3' 2>&1)"; rc=$?
check "explicit sh -c: exit 0" 0 "$rc"
check "explicit sh -c: recorded exit 3" 3 "$(jq -r '.runs[-1].exit' .veris/tasks/t/record.json)"

# 4. A second -- belongs to the command, as in `-- veris run ... -- uv run python -c '...'`.
#    Run 2's failing line, with a stand-in for veris that prints its last argument.
out="$(sh "$REC" red --task t --expect 'assertion=amount_cents=1500' -- \
  sh -c 'printf "%s\n" "$3"; exit 1' veris run -- 'r=s.refund(pi.id, amount_cents=1500)' 2>&1)"; rc=$?
check "nested --: exit 0" 0 "$rc"
check "nested --: last argument intact" 1 "$(printf '%s' "$out" | grep -cxF 'r=s.refund(pi.id, amount_cents=1500)')"

if [ "$fails" -eq 0 ]; then echo "record_argv: all passed"; else echo "record_argv: $fails failed"; exit 1; fi
