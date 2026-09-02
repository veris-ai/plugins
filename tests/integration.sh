#!/usr/bin/env sh
# End-to-end: stage the scripts the way setup does, then drive one whole task
# through the staged path — the way build and fix will actually call them.
#
# The unit tests exercise each script at its source path with every argument
# supplied. This exercises the seams: scripts invoked from .veris/bin/, and
# ledger.sh finding the base commit in record.json rather than being told it.
#
#   sh tests/integration.sh
set -u

ROOT="$(pwd)"
SRC_REF="$ROOT/veris-sim/skills/veris-reference/scripts"
SRC_SETUP="$ROOT/veris-sim/skills/setup/scripts"
[ -f "$SRC_REF/ledger.sh" ] || { echo "run from the repository root" >&2; exit 1; }

PASS=0; FAIL=0
ok()  { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '%s\n' "$2" | sed 's/^/         /' | head -8; FAIL=$((FAIL + 1)); }

step() { # step <name> <want-exit> <command...>
  name="$1"; want="$2"; shift 2
  out="$("$@" 2>&1)"; got=$?
  [ "$got" = "$want" ] && ok "$name" || bad "$name (wanted exit $want, got $got)" "$out"
}

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT INT TERM
cd "$TMP" || exit 1

printf '\nA repository that has never seen veris\n'

git init -q .; git config user.email t@t; git config user.name t
mkdir -p src dist
cat > src/pay.js <<'EOF'
// Mints a fresh key on every attempt — the defect.
function keyFor(attempt) { return "key-" + attempt; }
module.exports = { keyFor };
EOF
cat > build.sh <<'EOF'
#!/bin/sh
cp src/pay.js dist/pay.js
EOF
chmod +x build.sh; ./build.sh
cat > check.sh <<'EOF'
#!/bin/sh
# The twin's ledger stands in for /veris/data here.
node -e '
const {keyFor} = require("./dist/pay.js");
const keys = new Set([keyFor(1), keyFor(2)]);
require("fs").writeFileSync("ledger.txt", [...keys].join("\n"));
'
EOF
chmod +x check.sh
cat > predicate.sh <<'EOF'
#!/bin/sh
# Detects the defect: exits 0 when a retry produced a second distinct key.
[ "$(wc -l < ledger.txt)" -ge 1 ] && [ "$(sort -u ledger.txt | wc -l)" -gt 1 ]
EOF
chmod +x predicate.sh
echo 'work in progress, nothing to do with this task' > SCRATCH.md
git add -A; git commit -qm base
echo 'and an uncommitted line the engineer was already writing' >> SCRATCH.md
ok 'fixture built, with a pre-existing uncommitted change'

printf '\nWhat setup does\n'

mkdir -p .veris/bin
cp "$SRC_REF/ledger.sh" "$SRC_REF/record.sh" "$SRC_SETUP/preflight.sh" .veris/bin/
chmod +x .veris/bin/*.sh
cat > .veris/setup.json <<'EOF'
{
  "tier": "container",
  "environment_id": "env-fixture",
  "source_roots": ["src"],
  "build_command": "./build.sh",
  "build_outputs": ["dist"],
  "smoke_command": "./check.sh",
  "artifact_policy": "pr-body",
  "plugin_version": "0.6.5-rc.1"
}
EOF
printf '.veris/bin/\n.veris/tasks/\n' >> .gitignore
[ -x .veris/bin/ledger.sh ] && ok 'scripts staged into .veris/bin/' || bad 'staging failed'

# preflight's environment check is a live control-plane call, so the parts that
# depend on it cannot run here. Everything offline-decidable is asserted.
out="$(env VERIS_API_KEY=x VERIS_ENVIRONMENT_ID=env-fixture sh .veris/bin/preflight.sh --fast --plugin-version 0.6.5-rc.1 2>&1)"
printf '%s' "$out" | grep -q 'scripts     ok (staged from 0.6.5-rc.1)' \
  && ok 'preflight, run from .veris/bin/, matches the staged version' || bad 'staged-version check did not run' "$out"
printf '%s' "$out" | grep -q 'record      ok' \
  && ok 'and confirms record.sh will not degrade' || bad 'record fields not reported' "$out"
printf '%s' "$out" | grep -q 'FAIL environment' \
  && ok 'the environment check needs a live control plane (not exercised here)' || bad 'expected the env check to be the only blocker' "$out"

printf '\nOne task, start to finish, through the staged path\n'

T=fix-42
step 'gate 0: ledger init'  0 sh .veris/bin/ledger.sh init --task "$T"
step 'gate 1: record base'  0 sh .veris/bin/record.sh base --task "$T" --paths src/pay.js

./check.sh
step 'gate 1: red, on a command that exits 0 but leaves the wrong state' 0 \
  sh .veris/bin/record.sh red --task "$T" --expect predicate=./predicate.sh -- ./check.sh

# The fix, and the rebuild that must follow it.
cat > src/pay.js <<'EOF'
// One key per payment, reused across attempts.
function keyFor(_attempt) { return "key-stable"; }
module.exports = { keyFor };
EOF
./build.sh
step 'gate 3: green, once the predicate no longer finds the defect' 0 \
  sh .veris/bin/record.sh green --task "$T" --expect predicate=./predicate.sh -- ./check.sh

D=".veris/tasks/$T"
printf '{"idempotency_key":"key-stable","charges":1}\n' > "$D/snapshots/M01.json"
cat > "$D/measurements.jsonl" <<EOF
{"id":"M01","claim":"this twin stored one charge under a reused key","layer":"TWIN","probe":"POST /charges twice with the same key | jq .id","observed":"one charge row, id ch_1","evidence_ref":{"sandbox_id":"sbx-fixture","request_ids":["req_1","req_2"],"snapshot":"snapshots/M01.json","snapshot_sha256":"$(sha "$D/snapshots/M01.json")"},"decision":"reuse the key across attempts","code_ref":{"file":"src/pay.js","symbol":"keyFor"},"disposition":"ENCODED","counterfactual":null,"reviewer":null}
{"id":"M02","claim":"the vendor documents key replay for this case","layer":"VENDOR_CONTRACT","probe":"read the provider's idempotency page","observed":"silent — no guarantee either way","evidence_ref":{"silent":true},"decision":"do not build on replay","code_ref":{"file":"src/pay.js","decision_id":"no-replay-assumption"},"disposition":"NON_LOAD_BEARING","counterfactual":"had the page promised replay, the fix would be unchanged: it never relies on it"}
EOF

# The seam: no --base. It has to find the base commit in record.json.
step 'gate 4: ledger against the diff, finding the base commit itself' 0 \
  sh .veris/bin/ledger.sh --against-diff --task "$T"
out="$(sh .veris/bin/ledger.sh --against-diff --task "$T" 2>&1)"
printf '%s' "$out" | grep -q 'Ledger digest' && ok 'and prints a digest for the change description' || bad 'no digest' "$out"

out="$(sh .veris/bin/record.sh block --task "$T" 2>&1)"
printf '%s' "$out" | grep -q 'RED_EXPECTATION_MET'   && ok 'the record shows the red' || bad 'red missing' "$out"
printf '%s' "$out" | grep -q 'GREEN_EXPECTATION_MET' && ok 'the record shows the green' || bad 'green missing' "$out"

printf '\nThe pre-existing change was never touched\n'
git diff --quiet -- SCRATCH.md && bad 'SCRATCH.md was reverted — the engineer lost work' \
                               || ok 'the engineer'"'"'s uncommitted change survived the whole task'
# The campaign's own hygiene failure: agents run `git add -A` and sweep .veris/
# into the fix commit. The targeted ignores have to survive exactly that.
touch .veris/NOTES.md
git add -A
staged="$(git diff --cached --name-only)"
printf '%s' "$staged" | grep -q '.veris/setup.json' \
  && ok 'git add -A stages setup.json, which is meant to be committed' || bad 'setup.json not staged' "$staged"
printf '%s' "$staged" | grep -q '.veris/bin/' \
  && bad 'git add -A swept .veris/bin/ into the commit' "$staged" || ok 'and leaves .veris/bin/ out'
printf '%s' "$staged" | grep -q '.veris/tasks/' \
  && bad 'git add -A swept the task artifacts into the commit' "$staged" || ok 'and leaves .veris/tasks/ out'
git reset -q

printf '\nA hosted session: one task is one session, and the base dies with it\n'

H="$TMP/hosted"; mkdir -p "$H/src" "$H/dist"; cd "$H" || exit 1
git init -q .; git config user.email t@t; git config user.name t
cat > src/pay.js <<'EOF'
function keyFor(attempt) { return "key-" + attempt; }
module.exports = { keyFor };
EOF
printf '#!/bin/sh\ncp src/pay.js dist/pay.js\n' > build.sh; chmod +x build.sh; ./build.sh
git add -A; git commit -qm base

# What setup's section 0 leaves on this tier: the scripts fetched into
# .veris/bin/, a setup.json it wrote itself, and the session file with the
# twin beside the readings. No run.sh; no key or environment id in the shell.
mkdir -p .veris/bin
cp "$SRC_REF/ledger.sh" "$SRC_REF/record.sh" "$SRC_SETUP/preflight.sh" .veris/bin/
chmod +x .veris/bin/*.sh
cat > .veris/setup.json <<'EOF'
{
  "tier": "hosted",
  "source_roots": ["src"],
  "build_command": "./build.sh",
  "build_outputs": ["dist"],
  "smoke_command": "./build.sh",
  "artifact_policy": "pr-body",
  "plugin_version": "0.6.5-rc.1"
}
EOF
cat > .veris/session.md <<'EOF'
twin: sbx-fixture
tier: hosted
lifecycle: session
control_url: pay https://pay-fixture.twin.example
egress: boundary-refused    # 403, body begins "egress: host not allowlisted"
staging: npm 0.6.5-rc.1
issue_and_pr: engineer
run: ./build.sh
receipt: the receipt tool, called with no argument
EOF
printf '.veris/bin/\n.veris/tasks/\n.veris/session.md\n' >> .gitignore

out="$(env -u VERIS_API_KEY -u VERIS_ENVIRONMENT_ID sh .veris/bin/preflight.sh --hosted --plugin-version 0.6.5-rc.1 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && ok 'preflight --hosted holds with no key, no environment id and no run.sh' \
               || bad "preflight --hosted failed (exit $rc)" "$out"
printf '%s' "$out" | grep -q 'scripts     ok (staged from 0.6.5-rc.1)' \
  && ok 'and matches the version the session staged' || bad 'staged-version check did not run' "$out"
printf '%s' "$out" | grep -q 'session     ok' \
  && ok 'and reads the twin and the run command from session.md' || bad 'session.md not read' "$out"

T=fix-7
step 'gate 0: ledger init'  0 sh .veris/bin/ledger.sh init --task "$T"
step 'gate 1: record base'  0 sh .veris/bin/record.sh base --task "$T" --paths src/pay.js
step 'gate 1: a baseline run against the pinned source' 0 \
  sh .veris/bin/record.sh red --task "$T" --expect baseline -- ./build.sh
[ -f ".veris/tasks/$T/record.json" ] && ok 'the base is pinned in record.json' || bad 'no record.json after base'

# The session ends. The next sandbox is fresh: .veris/tasks/ is gitignored, so
# the pin is gone. A new session claims the same task id and opens a ledger.
rm -rf .veris/tasks
step 'next session: gate 0 again, same task id' 0 sh .veris/bin/ledger.sh init --task "$T"
echo 'function keyFor(_attempt) { return "key-stable"; }' > src/pay.js; ./build.sh
D=".veris/tasks/$T"
printf '{"idempotency_key":"key-stable","charges":1}\n' > "$D/snapshots/M01.json"
cat > "$D/measurements.jsonl" <<EOF
{"id":"M01","claim":"this twin stored one charge under a reused key","layer":"TWIN","probe":"POST /charges twice with the same key | jq .id","observed":"one charge row","evidence_ref":{"sandbox_id":"sbx-fixture","request_ids":["req_1"],"snapshot":"snapshots/M01.json","snapshot_sha256":"$(sha "$D/snapshots/M01.json")"},"decision":"reuse the key across attempts","code_ref":{"file":"src/pay.js","symbol":"keyFor"},"disposition":"ENCODED","counterfactual":null}
EOF
step 'gate 4: the ledger refuses a base that died with the last session' 1 \
  sh .veris/bin/ledger.sh --against-diff --task "$T"
out="$(sh .veris/bin/ledger.sh --against-diff --task "$T" 2>&1)"
printf '%s' "$out" | grep -qF "no base commit: run 'record.sh base' when the task starts" \
  && ok 'and names the unpinned base, not the rows' || bad 'the unpinned base was not the reason given' "$out"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
