#!/usr/bin/env bash
# One command to go from nothing to a runnable harness.
#
#   ./setup.sh            install deps, then check every key and report
#   ./setup.sh --create-env  also create a Veris environment if you have none
#
# Idempotent: re-run it any time. It never writes to your shell profile and it
# never prints a key back to you.
set -uo pipefail
cd "$(dirname "$0")"

API_BASE="${VERIS_API_BASE:-https://svc.api.veris.ai}"
CREATE_ENV=false
[ "${1:-}" = "--create-env" ] && CREATE_ENV=true

bold() { printf '\n\033[1m▸ %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
info() { printf '    %s\n' "$1"; }
READY=true

# The SDK is cloned in here rather than beside the repo, so the harness is one
# self-contained directory you can move or delete. Override with VERIS_E2B_DIR
# if you already have a checkout you are editing.
SDK_DIR="${VERIS_E2B_DIR:-$PWD/.veris-e2b}"

# ---------------------------------------------------------------- deps
bold "SDK"
for bin in git node npm jq curl; do
  command -v "$bin" >/dev/null 2>&1 || {
    bad "$bin is not on PATH"
    [ "$bin" = jq ] && info "macOS: brew install jq · Debian: apt-get install -y jq"
    exit 1; }
done
# @veris-ai/e2b is not on npm yet, so it is consumed from a local checkout.
if [ ! -d "$SDK_DIR" ]; then
  info "cloning veris-ai/veris-e2b → ${SDK_DIR/#$PWD\//}…"
  git clone -q --depth 1 https://github.com/veris-ai/veris-e2b "$SDK_DIR" || {
    bad "clone failed — do you have access to veris-ai/veris-e2b?"; exit 1; }
fi
( cd "$SDK_DIR" && npm ci --silent && npm run build --silent ) >/dev/null 2>&1 || {
  bad "veris-e2b failed to build — try: cd ${SDK_DIR/#$PWD\//} && npm ci && npm run build"; exit 1; }
ok "@veris-ai/e2b built at $(node -p "require('$SDK_DIR/package.json').version")"

# The file: dependency is written here rather than hand-edited.
cat > package.json <<JSON
{
  "name": "opencode-e2b-e2e",
  "private": true,
  "type": "module",
  "dependencies": { "@veris-ai/e2b": "file:$SDK_DIR" }
}
JSON

# Nothing in here belongs in git: a vendored checkout, node_modules, and a
# package.json whose only content is an absolute path to this machine.
cat > .gitignore <<'IGNORE'
.veris-e2b/
node_modules/
package.json
package-lock.json
IGNORE
npm install --silent >/dev/null 2>&1 || { bad "npm install failed"; exit 1; }
ok "harness dependencies installed"

# ---------------------------------------------------------------- keys
bold "Keys"

if [ -n "${E2B_API_KEY:-}" ]; then ok "E2B_API_KEY set"; else
  READY=false; bad "E2B_API_KEY not set"
  info "get one at https://e2b.dev/dashboard → API Keys (free tier works)"
fi

if [ -n "${ANTHROPIC_API_KEY:-}${OPENAI_API_KEY:-}" ]; then
  ok "model provider key set"
else
  READY=false; bad "ANTHROPIC_API_KEY (or OPENAI_API_KEY) not set"
  info "https://console.anthropic.com/settings/keys — the agent runs INSIDE the"
  info "sandbox, so it needs a raw key; your local 'opencode auth' won't travel"
fi

if [ -z "${VERIS_API_KEY:-}" ]; then
  READY=false; bad "VERIS_API_KEY not set"
  info "from your Veris dashboard, or ask in #eng"
else
  ok "VERIS_API_KEY set"

  # ------------------------------------------------------------ environment
  bold "Veris environment"
  envs="$(curl -sS -m 20 -H "X-API-Key: $VERIS_API_KEY" "$API_BASE/v1/environments" 2>/dev/null)"
  if [ -z "$envs" ] || ! printf '%s' "$envs" | jq -e . >/dev/null 2>&1; then
    READY=false; bad "could not list environments from $API_BASE"
    info "check VERIS_API_KEY, or VERIS_API_BASE if you are not on production"
  else
    count="$(printf '%s' "$envs" | jq '[.. | objects | select(has("id") and has("name"))] | length')"
    if [ "${VERIS_ENVIRONMENT_ID:-}" != "" ]; then
      name="$(printf '%s' "$envs" | jq -r --arg id "$VERIS_ENVIRONMENT_ID" \
        '[.. | objects | select(.id? == $id)] | first | .name // empty')"
      if [ -n "$name" ]; then ok "VERIS_ENVIRONMENT_ID → \"$name\""
      else READY=false; bad "VERIS_ENVIRONMENT_ID is set but not in your account"; fi
    elif [ "$count" -gt 0 ]; then
      READY=false; bad "VERIS_ENVIRONMENT_ID not set. Yours:"
      printf '%s' "$envs" | jq -r '[.. | objects | select(has("id") and has("name"))][]
        | "      export VERIS_ENVIRONMENT_ID=\(.id)   # \(.name)"'
    elif [ "$CREATE_ENV" = true ]; then
      info "no environments — creating one with stripe…"
      created="$(curl -sS -m 30 -X POST "$API_BASE/v1/environments" \
        -H "X-API-Key: $VERIS_API_KEY" -H 'Content-Type: application/json' \
        -d '{"name":"opencode-e2e","services":["stripe"]}' 2>/dev/null)"
      new_id="$(printf '%s' "$created" | jq -r '.id // empty')"
      if [ -n "$new_id" ]; then
        READY=false; ok "created \"opencode-e2e\""
        info "export VERIS_ENVIRONMENT_ID=$new_id"
      else
        READY=false; bad "create failed: $(printf '%s' "$created" | head -c 200)"
        info "see the catalogue: curl -sS -H \"X-API-Key: \$VERIS_API_KEY\" $API_BASE/v1/services | jq"
      fi
    else
      READY=false; bad "no environments in this account"
      info "re-run as: ./setup.sh --create-env"
    fi
  fi
fi

bold "Result"
if [ "$READY" = true ]; then
  ok "ready — run:  node e2e.mjs   (or: node e2e.mjs --attach)"
else
  bad "export what is missing above, then re-run ./setup.sh"
  exit 1
fi
