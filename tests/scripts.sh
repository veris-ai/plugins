#!/usr/bin/env sh
# Unit tests for the shipped scripts. Every case is one the campaign actually
# produced, or one a reviewer asked whether the script would catch.
#
#   sh tests/scripts.sh
#
# Exit: 0 all green · 1 at least one case failed.
set -u

ROOT="$(pwd)"
LEDGER="$ROOT/veris-sim/skills/veris-reference/scripts/ledger.sh"
RECORD="$ROOT/veris-sim/skills/veris-reference/scripts/record.sh"
PREFLIGHT="$ROOT/veris-sim/skills/setup/scripts/preflight.sh"
[ -f "$LEDGER" ] || { echo "run from the repository root" >&2; exit 1; }

PASS=0; FAIL=0
head_() { printf '\n%s\n' "$1"; }

# t <name> <want-exit> <command...>  — runs it, compares the exit code.
t() {
  name="$1"; want="$2"; shift 2
  out="$("$@" 2>&1)"; got=$?
  if [ "$got" = "$want" ]; then
    printf '  ok   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL %s (wanted exit %s, got %s)\n' "$name" "$want" "$got"
    printf '%s\n' "$out" | sed 's/^/         /' | head -6
    FAIL=$((FAIL + 1))
  fi
}

# t_out <name> <substring> <command...> — runs it, requires the substring.
t_out() {
  name="$1"; want="$2"; shift 2
  out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF "$want"; then
    printf '  ok   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  FAIL %s (output lacks "%s")\n' "$name" "$want"
    printf '%s\n' "$out" | sed 's/^/         /' | head -6
    FAIL=$((FAIL + 1))
  fi
}

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT INT TERM

# ============================================================ ledger.sh

head_ 'ledger.sh'

L="$TMP/ledger"; mkdir -p "$L"; cd "$L" || exit 1
git init -q .; git config user.email t@t; git config user.name t
echo 'function capture(){}' > app.js
git add -A; git commit -qm base
BASE="$(git rev-parse HEAD)"

t 'init creates the task directory' 0 sh "$LEDGER" init --task T
D='.veris/tasks/T'
[ -d "$D/snapshots" ] && { printf '  ok   init made snapshots/\n'; PASS=$((PASS+1)); } \
                      || { printf '  FAIL init made no snapshots/\n'; FAIL=$((FAIL+1)); }

printf '{"replayed":"402","rows":2}\n' > "$D/snapshots/M01.json"
SNAP="$(sha "$D/snapshots/M01.json")"

row() { # row <id> <layer> <disposition> <extra json> ; writes one ledger
  cat > "$D/measurements.jsonl" <<EOF
{"id":"$1","claim":"c","layer":$2,"probe":"read the trace | jq .status","observed":"o","decision":"d","disposition":"$3",$4}
EOF
}
TWIN_EV="\"evidence_ref\":{\"sandbox_id\":\"s1\",\"request_ids\":[\"r1\"],\"snapshot\":\"snapshots/M01.json\",\"snapshot_sha256\":\"$SNAP\"},\"code_ref\":{\"file\":\"app.js\",\"symbol\":\"capture\"}"
REPO_EV='"evidence_ref":{"test":"t.spec"},"code_ref":{"file":"app.js","symbol":"capture"}'

row V1 '"TWIN"' ENCODED "$TWIN_EV"
t 'a well-formed row passes, pipes in the probe and all' 0 sh "$LEDGER" check --task T

row V2 '"VENDOR_CONTRACT"' NON_LOAD_BEARING '"evidence_ref":{"silent":true},"code_ref":{"file":"app.js","decision_id":"d1"},"counterfactual":"had the docs promised replay the design would not change"'
t 'documentation silence is a recordable result' 0 sh "$LEDGER" check --task T

row B1 '"REPOSITORY"' NON_LOAD_BEARING "$REPO_EV"
t 'NON_LOAD_BEARING without a counterfactual fails' 2 sh "$LEDGER" check --task T

row B2 '"TWIN"' ENCODED '"evidence_ref":{"sandbox_id":"s1","request_ids":["r1"]},"code_ref":{"file":"app.js","symbol":"capture"}'
t 'a TWIN row with ids but no snapshot fails' 2 sh "$LEDGER" check --task T
t_out 'and it says why ids are not enough' 'stop resolving' sh "$LEDGER" check --task T

row B3 '"TWIN"' ENCODED '"evidence_ref":{"snapshot":"snapshots/M01.json","snapshot_sha256":"deadbeef"},"code_ref":{"file":"app.js","symbol":"capture"}'
t 'a snapshot whose digest moved fails' 2 sh "$LEDGER" check --task T

row B4 '["TWIN","REPOSITORY"]' ENCODED "$REPO_EV"
t 'a row claiming two layers fails' 2 sh "$LEDGER" check --task T

row B5 '"REPOSITORY"' ENCODED '"evidence_ref":{"test":"t"},"code_ref":{"file":"app.js","line":42}'
t 'code_ref with only a line number fails' 2 sh "$LEDGER" check --task T

row B6 '"REPOSITORY"' NONSENSE "$REPO_EV"
t 'an unknown disposition fails' 2 sh "$LEDGER" check --task T

printf 'not json at all\n' > "$D/measurements.jsonl"
t 'a line that is not JSON fails' 2 sh "$LEDGER" check --task T

# The negative test: judging whether a sentence spans layers is a person's job.
cat > "$D/measurements.jsonl" <<EOF
{"id":"N1","claim":"a retry after a lost response does not charge the customer twice, end to end","layer":"TWIN","probe":"p","observed":"o","decision":"d","disposition":"ENCODED",$TWIN_EV}
EOF
t 'a semantically compound claim is ACCEPTED — the grader judges it, not the script' 0 sh "$LEDGER" check --task T

row S1 '"REPOSITORY"' ENCODED '"evidence_ref":{"test":"export T=ghp_abcdefghijklmnopqrstuvwxyz0123456789"},"code_ref":{"file":"app.js","symbol":"capture"}'
t 'a credential in a row is refused' 2 sh "$LEDGER" check --task T

printf '{"authorization":"AKIAIOSFODNN7EXAMPLE"}\n' > "$D/snapshots/S2.json"
S2="$(sha "$D/snapshots/S2.json")"
cat > "$D/measurements.jsonl" <<EOF
{"id":"S2","claim":"c","layer":"TWIN","probe":"p","observed":"o","decision":"d","disposition":"ENCODED","evidence_ref":{"snapshot":"snapshots/S2.json","snapshot_sha256":"$S2"},"code_ref":{"file":"app.js","symbol":"capture"}}
EOF
t 'a credential in a snapshot is refused' 2 sh "$LEDGER" check --task T
rm -f "$D/snapshots/S2.json"

row F1 '"TWIN"' ENCODED "$TWIN_EV"
t_out 'prose mentioning an API key is not a credential' 'ok' sh "$LEDGER" check --task T

row X1 '"TRANSPORT"' ENCODED "$TWIN_EV"
t 'a layer that was cut is no longer accepted' 2 sh "$LEDGER" check --task T

# --against-diff
row A1 '"TWIN"' CONTRADICTED "$TWIN_EV"
t 'CONTRADICTED closes the gate as a failure' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"
t_out 'and it says to change the code, not the report' 'Change the code' sh "$LEDGER" --against-diff --task T --base "$BASE"

row A2 '"TWIN"' UNRESOLVED "$TWIN_EV"
t 'UNRESOLVED closes the gate as a failure' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"

row A3 '"TWIN"' ENCODED "$TWIN_EV"
t 'ENCODED naming a file the change never touched fails' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"

echo 'function capture(){ return 1; }' > app.js
t 'ENCODED naming a changed file passes' 0 sh "$LEDGER" --against-diff --task T --base "$BASE"
t_out 'and prints a digest for the change description' 'Ledger digest' sh "$LEDGER" --against-diff --task T --base "$BASE"

cat > "$D/measurements.jsonl" <<EOF
{"id":"R1","claim":"c","layer":"TWIN","probe":"p","observed":"o","decision":"d","disposition":"ENCODED","evidence_ref":{"sandbox_id":"s","request_ids":["r"],"snapshot":"snapshots/M01.json","snapshot_sha256":"$SNAP"},"code_ref":{"file":"app.js","symbol":"aRenamedThing"}}
EOF
t 'a symbol missing from the hunks warns but does not fail' 0 sh "$LEDGER" --against-diff --task T --base "$BASE"

t 'no task id is a usage error' 1 sh "$LEDGER" check

# Retrodictive cases — the campaign's two sharpest misses, reconstructed from
# the measurements those runs published and the diffs they shipped. Rows B and C
# are the documented ceiling: the check reads structure, never meaning.
retro() { # retro <disposition> <counterfactual-json> <file>
  cat > "$D/measurements.jsonl" <<EOF
{"id":"R","claim":"this twin replayed the cached decline on a same-key retry: 0 charges, capture stays failed","layer":"TWIN","probe":"arm 402 card_declined, capture, capture again with the same key","observed":"replays the cached decline; 0 charges captured","evidence_ref":{"sandbox_id":"s","request_ids":["c1","c2"],"snapshot":"snapshots/M01.json","snapshot_sha256":"$SNAP"},"decision":"reuse the key on retry, or rotate","code_ref":{"file":"$3","symbol":"capture"},"disposition":"$1","counterfactual":$2}
EOF
}
retro CONTRADICTED null app.js
t 'retro: a measured rule the diff contradicts fails the gate' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"
retro NON_LOAD_BEARING null app.js
t 'retro: dodging it without a counterfactual fails' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"
retro ENCODED null nowhere.js
t 'retro: parking it against untouched code fails' 2 sh "$LEDGER" --against-diff --task T --base "$BASE"
retro ENCODED null app.js
t 'retro: CEILING — marking the contradiction ENCODED passes; only a reader catches it' 0 sh "$LEDGER" --against-diff --task T --base "$BASE"
retro NON_LOAD_BEARING '"had the twin replayed nothing the fix would be unchanged"' app.js
t 'retro: CEILING — a false counterfactual passes; it is falsifiable, not checked' 0 sh "$LEDGER" --against-diff --task T --base "$BASE"

# ============================================================ record.sh

head_ 'record.sh'

R="$TMP/record"; mkdir -p "$R/src" "$R/dist" "$R/.veris"; cd "$R" || exit 1
git init -q .; git config user.email t@t; git config user.name t
echo 'function capture(){ return "BUG"; }' > src/app.js
echo 'a line the engineer was already editing' > README.md
cat > .veris/setup.json <<'EOF'
{"tier":"container","source_roots":["src"],"build_command":"cp src/app.js dist/app.js","build_outputs":["dist"]}
EOF
cp src/app.js dist/app.js
git add -A; git commit -qm base
echo 'and an uncommitted one' >> README.md      # a pre-existing user change

cat > test.sh <<'EOF'
#!/bin/sh
grep -q '"OK"' dist/app.js && echo PASS || { echo "FAIL: capture returned BUG"; exit 1; }
EOF
chmod +x test.sh

t 'base does not refuse a worktree that already had changes' 0 sh "$RECORD" base --task T1 --paths src/app.js
t_out 'and records them rather than forbidding them' 'recorded, not forbidden' sh "$RECORD" base --task T1 --paths src/app.js

# The medusa shape: the source was put back, the build still carries the fix.
# Detected by content, so it does not depend on clock granularity.
echo 'function capture(){ return "OK"; }' > dist/app.js
t 'a red whose build no longer matches the pinned source is refused' 2 sh "$RECORD" red --task T1 --expect nonzero -- ./test.sh
t_out 'and it names the rebuild command' 'cp src/app.js dist/app.js' sh "$RECORD" red --task T1 --expect nonzero -- ./test.sh
cp src/app.js dist/app.js

# Staleness is decided by content, not by mtime: touching the source alone is
# not evidence the build is stale, and refusing on it would be a false alarm.
sleep 1; touch src/app.js
t 'a touched source with a matching build is not refused' 0 sh "$RECORD" red --task T1 --expect nonzero -- ./test.sh
t 'a genuine red meets --expect nonzero' 0 sh "$RECORD" red --task T1 --expect nonzero -- ./test.sh
t 'a red that passes does not meet an assertion' 2 sh "$RECORD" red --task T1 --expect assertion=BUG -- 'echo "Tests: 49 skipped, 2 passed"'
t_out 'and says the failure is the finding' 'That is the finding' sh "$RECORD" red --task T1 --expect assertion=BUG -- 'echo "2 passed"'

sed 's/BUG/OK/' src/app.js > src/app.js.new && mv src/app.js.new src/app.js
t 'a red after the source moved is refused' 2 sh "$RECORD" red --task T1 --expect nonzero -- ./test.sh
cp src/app.js dist/app.js
t 'green meets --expect nonzero when the test now passes' 0 sh "$RECORD" green --task T1 --expect nonzero -- ./test.sh

# The predicate: it detects the defect, so exit 0 means the defect is present.
printf 'charge\ncharge\n' > ledger.txt
cat > predicate.sh <<'EOF'
#!/bin/sh
[ "$(grep -c charge ledger.txt)" -gt 1 ]
EOF
chmod +x predicate.sh
sh "$RECORD" base --task T2 --paths src/app.js >/dev/null 2>&1
t 'a command exiting 0 is still a red when the predicate finds the defect' 0 \
  sh "$RECORD" red --task T2 --expect predicate=./predicate.sh -- 'echo "HTTP 200 OK"'
t 'green fails while the predicate still finds the defect' 2 \
  sh "$RECORD" green --task T2 --expect predicate=./predicate.sh -- 'echo "HTTP 200 OK"'
printf 'charge\n' > ledger.txt
t 'green passes once the predicate no longer finds it' 0 \
  sh "$RECORD" green --task T2 --expect predicate=./predicate.sh -- 'echo "HTTP 200 OK"'

t_out 'block prints the record, and calls itself a record' 'not a proof' sh "$RECORD" block --task T2

# A nested build output must not read as "moved" just because the re-scan
# recovered the wrong directory from the file list.
mkdir -p dist/nested
cp src/app.js dist/nested/deep.js
echo 'sibling' > dist/sibling.js
cat > .veris/setup.json <<'EOF'
{"source_roots":["src"],"build_command":"make","build_outputs":["dist"]}
EOF
sh "$RECORD" base --task T5 --paths src/app.js >/dev/null 2>&1
t 'a nested build output does not read as moved' 0 sh "$RECORD" red --task T5 --expect baseline -- 'true'
echo 'tampered' > dist/nested/deep.js
t 'but a build output that really moved is caught' 2 sh "$RECORD" red --task T5 --expect baseline -- 'true'
rm -rf dist/nested dist/sibling.js

echo '{"source_roots":["src"]}' > .veris/setup.json
t_out 'no build_command degrades rather than refusing' 'BUILD_PROVENANCE_UNKNOWN' sh "$RECORD" base --task T3 --paths src/app.js
t_out 'no --paths falls back to source_roots and says so' 'PATHS_UNNARROWED' sh "$RECORD" base --task T4
t 'an unknown --expect is a usage error' 1 sh "$RECORD" red --task T4 --expect bogus -- true
t 'red before base is a usage error' 1 sh "$RECORD" red --task T9 --expect nonzero -- true

# ============================================================ preflight.sh

head_ 'preflight.sh'

cd "$R" || exit 1
t 'preflight reports every blocker in one pass' 2 env -u VERIS_API_KEY -u VERIS_ENVIRONMENT_ID sh "$PREFLIGHT"
out="$(env -u VERIS_API_KEY -u VERIS_ENVIRONMENT_ID sh "$PREFLIGHT" 2>&1)"
n="$(printf '%s\n' "$out" | grep -c 'FAIL')"
if [ "$n" -ge 2 ]; then printf '  ok   more than one blocker in a single run (%s)\n' "$n"; PASS=$((PASS+1))
else printf '  FAIL only %s blocker reported; it should not stop at the first\n' "$n"; FAIL=$((FAIL+1)); fi
mkdir -p .veris/bin
for s in ledger.sh record.sh preflight.sh; do : > ".veris/bin/$s"; done
t_out 'staged scripts with no --plugin-version say VERSION_UNCHECKED' 'VERSION_UNCHECKED' \
  env -u VERIS_API_KEY sh "$PREFLIGHT"
printf '{"source_roots":["src"],"plugin_version":"0.6.5-rc.1"}\n' > .veris/setup.json
t_out 'a matching plugin version is ok' 'staged from 0.6.5-rc.1' \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --plugin-version 0.6.5-rc.1
t_out 'a stale staging is named as stale' 'stale scripts' \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --plugin-version 0.6.6
rm -f .veris/bin/ledger.sh
t_out 'an incomplete staging is caught' 'staged scripts are incomplete' \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --plugin-version 0.6.5-rc.1

# --hosted: inside a session-provisioned sandbox the key, the environment id,
# the proxy and docker are the host's; preflight has nothing to check and must
# not fail for their absence. Shims make the last two fail wherever this
# runs, so a mode that stops skipping them is caught.
mkdir -p "$TMP/shim"
for b in docker veris-proxy; do printf '#!/bin/sh\nexit 1\n' > "$TMP/shim/$b"; chmod +x "$TMP/shim/$b"; done
: > .veris/bin/ledger.sh
printf '{"tier":"hosted","source_roots":["src"],"plugin_version":"0.6.5-rc.1"}\n' > .veris/setup.json
t '--hosted holds with no key, no environment, no proxy and no docker' 0 \
  env -u VERIS_API_KEY -u VERIS_ENVIRONMENT_ID PATH="$TMP/shim:$PATH" sh "$PREFLIGHT" --hosted
t_out 'and reads the tier from setup.json' 'setup.json (hosted tier)' \
  env -u VERIS_API_KEY -u VERIS_ENVIRONMENT_ID PATH="$TMP/shim:$PATH" sh "$PREFLIGHT" --hosted
t_out '--hosted matches the staged version' 'staged from 0.6.5-rc.1' \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --hosted --plugin-version 0.6.5-rc.1
t_out '--hosted still names a stale staging' 'stale scripts' \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --hosted --plugin-version 0.6.6
rm -rf .veris/bin
t '--hosted with nothing staged fails — setup fetches the scripts every session' 2 \
  env -u VERIS_API_KEY sh "$PREFLIGHT" --hosted
t_out 'and says so' 'not staged' env -u VERIS_API_KEY sh "$PREFLIGHT" --hosted

# ================================================================== verdict

cd "$ROOT" || exit 1
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
