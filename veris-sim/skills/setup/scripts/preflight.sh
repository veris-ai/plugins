#!/usr/bin/env sh
# Asserts the preconditions for `veris-proxy run`, and reports every one that
# fails in a single pass — one round trip, not one per blocker. Run by
# /veris-sim:setup; run it before every session rather than trusting that setup
# still holds.
#
#   preflight.sh                                  uses VERIS_ENVIRONMENT_ID and .veris/setup.json
#   preflight.sh <env-id>                         checks a different environment
#   preflight.sh --direct [<env-id>]              direct tier: credential + environment only
#   preflight.sh --fast [<env-id>]                already wired? say so and stop
#   preflight.sh --plugin-version <v> [<env-id>]  also check the staged scripts are current
#   preflight.sh --hosted [--plugin-version <v>]  hosted tier: jq and the staged scripts — nothing the sandbox cannot see
#
# Exit: 0 everything holds · 2 at least one precondition failed.
set -u

FAILED=0
fail() { printf 'preflight: FAIL %-11s %s\n' "$1" "$2" >&2; FAILED=$((FAILED + 1)); }
skip() { printf 'preflight: %-16s skipped (depends on %s)\n' "$1" "$2"; }
ok()   { printf 'preflight: %-11s ok%s\n' "$1" "${2:+ ($2)}"; }
note() { printf 'preflight: %-11s %s\n' "$1" "$2"; }

base="${VERIS_API_BASE:-https://svc.api.veris.ai}"
base="${base%/}"

direct=0
fast=0
hosted=0
plugin_version=''
while [ $# -gt 0 ]; do
  case "$1" in
    --direct)         direct=1; shift ;;
    --fast)           fast=1; shift ;;
    --hosted)         hosted=1; shift ;;
    --plugin-version) plugin_version="${2:-}"; [ -n "$plugin_version" ] || { echo "preflight: --plugin-version needs a value" >&2; exit 2; }; shift 2 ;;
    *)                break ;;
  esac
done

setup_get() { [ -f .veris/setup.json ] && sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" .veris/setup.json | head -1 || true; }
setup_has() { [ -f .veris/setup.json ] && grep -q "\"$1\"" .veris/setup.json; }

# ------------------------------------------------------------------ credential

if [ "$hosted" = 1 ]; then
  note credential "hosted tier — the session's sandbox already holds the twin; the key is the host's, not checked here"
  have_key=0
elif [ -n "${VERIS_API_KEY:-}" ]; then
  ok credential
  have_key=1
else
  fail credential "VERIS_API_KEY is not set in this shell"
  have_key=0
fi

# ------------------------------------------------------------------- transport

if [ "$hosted" = 1 ]; then
  note transport "hosted tier — the session provisioned the sandbox; binary/docker/image not required"
elif [ "$direct" = 1 ]; then
  note transport "direct tier — binary/docker/image not required"
else
  if command -v veris-proxy >/dev/null 2>&1 && veris-proxy version >/dev/null 2>&1; then
    ok binary "$(veris-proxy version 2>/dev/null | head -1)"
  else
    fail binary "veris-proxy is not on PATH or does not run; ask the user, then: curl -fsSL https://raw.githubusercontent.com/veris-ai/veris-proxy/main/scripts/install.sh | sh  (a static binary into ~/.local/bin, no root)"
  fi

  if docker version >/dev/null 2>&1; then
    ok docker
  else
    fail docker "no docker daemon reachable (local socket or DOCKER_HOST); start one. No daemon reachable from here: stop and tell the user"
  fi
fi

# Every projection example in the skills pipes through jq, and every ledger row
# is JSON; without it they fail as a shell error rather than as evidence.
if command -v jq >/dev/null 2>&1; then
  ok jq
else
  fail jq "jq is not on PATH; install it (macOS: brew install jq / Debian: apt-get install -y jq)"
fi

# ------------------------------------------------------------------ environment

env_id="${1:-${VERIS_ENVIRONMENT_ID:-}}"
if [ "$hosted" = 1 ]; then
  note environment "hosted tier — the environment id is a host-side variable the sandbox never sees; not checked"
elif [ -z "$env_id" ]; then
  fail environment "export VERIS_ENVIRONMENT_ID or pass an environment id"
elif [ "$have_key" = 0 ]; then
  skip environment credential
else
  body="$(curl --fail-with-body -sS -m 20 -H "X-API-Key: $VERIS_API_KEY" "$base/v1/environments/$env_id" 2>/dev/null)" || body=''
  case "$body" in
    '')        fail environment "control plane $base unreachable, or it refused the key" ;;
    *'"id"'*)
      case "$body" in
        *'"baseline"'*'"image"'*) ok environment "$env_id, promoted world" ;;
        *)                        ok environment "$env_id, no promoted world — every sandbox boots the default world" ;;
      esac ;;
    *)         fail environment "control plane refused the key or does not know $env_id: $(printf '%s' "$body" | cut -c1-120)" ;;
  esac
fi

# ------------------------------------------------------------------------ image

if [ "$direct" != 1 ] && [ "$hosted" != 1 ] && [ -f .veris/setup.json ]; then
  image="$(setup_get image)"
  dockerfile="$(setup_get dockerfile)"
  # A stock image is pulled by the run itself; only a tag built from a recorded
  # Dockerfile has to exist locally before the run can start.
  if [ -n "$image" ] && [ -n "$dockerfile" ]; then
    if ! docker version >/dev/null 2>&1; then
      skip image docker
    elif docker image inspect "$image" >/dev/null 2>&1; then
      ok image "$image"
    else
      fail image "$image (built from $dockerfile, per .veris/setup.json) is not built; docker build -f $dockerfile -t $image ."
    fi
  elif [ -n "$image" ]; then
    ok image "$image (stock image; the run pulls it)"
  fi
fi

# ------------------------------------------------------------- staged scripts

if [ -d .veris/bin ]; then
  missing=''
  for s in ledger.sh record.sh preflight.sh; do
    [ -f ".veris/bin/$s" ] || missing="$missing $s"
  done
  if [ -n "$missing" ]; then
    fail scripts "staged scripts are incomplete —$missing; re-run /veris-sim:setup"
  else
    recorded="$(setup_get plugin_version)"
    if [ -z "$plugin_version" ]; then
      note scripts "staged, VERSION_UNCHECKED — pass --plugin-version to compare"
    elif [ -z "$recorded" ]; then
      fail scripts "no plugin_version in .veris/setup.json; re-run /veris-sim:setup"
    elif [ "$recorded" = "$plugin_version" ]; then
      ok scripts "staged from $recorded"
    else
      fail scripts "stale scripts — staged from $recorded, running $plugin_version; re-run /veris-sim:setup"
    fi
  fi
else
  if [ "$hosted" = 1 ]; then
    fail scripts "not staged — on the hosted tier setup fetches them into .veris/bin/ every session, and Gate 4 has no route without them; re-run /veris-sim:setup"
  else
    note scripts "not staged yet (setup copies them into .veris/bin/)"
  fi
fi

# ------------------------------------------------------- what later tasks need

if [ -f .veris/setup.json ]; then
  missing=''
  setup_has source_roots  || missing="$missing source_roots"
  setup_has build_command || missing="$missing build_command"
  setup_has build_outputs || missing="$missing build_outputs"
  if [ -n "$missing" ]; then
    note record "record.sh will degrade — .veris/setup.json lacks:$missing"
  else
    ok record "source_roots, build_command and build_outputs recorded"
  fi
fi

# ------------------------------------------------------------------- artifacts

if [ "$hosted" = 1 ]; then
  if [ -f .veris/setup.json ] && grep -q '"tier"[[:space:]]*:[[:space:]]*"hosted"' .veris/setup.json; then
    ok setup ".veris/setup.json (hosted tier)"
  else
    note setup "not yet recorded (hosted tier writes .veris/setup.json, no run.sh)"
  fi
elif [ "$direct" = 1 ]; then
  if [ -f .veris/setup.json ] && grep -q '"tier"[[:space:]]*:[[:space:]]*"direct"' .veris/setup.json; then
    ok setup ".veris/setup.json (direct tier)"
  else
    note setup "not yet recorded (direct tier writes .veris/setup.json, no run.sh)"
  fi
else
  if [ -f .veris/run.sh ]; then ok run.sh ".veris/run.sh recorded"
  else note run.sh "not yet recorded"; fi
fi

# --------------------------------------------------------------------- verdict

if [ "$FAILED" -gt 0 ]; then
  printf 'preflight: %d precondition(s) failed. Fix them together, then run this again.\n' "$FAILED" >&2
  exit 2
fi

if [ "$fast" = 1 ]; then
  smoke="$(setup_get smoke_command)"
  if [ -n "$smoke" ]; then
    printf 'preflight: setup holds. Smallest verified smoke command:\n  %s\n' "$smoke"
  else
    printf 'preflight: preconditions hold, but no smoke_command is recorded — setup is not finished.\n'
    exit 2
  fi
fi
exit 0
