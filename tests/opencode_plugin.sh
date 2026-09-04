#!/usr/bin/env sh
# The OpenCode plugin registers the three commands and nothing else: no MCP
# server, so a machine signed in with `veris login` (no VERIS_API_KEY in the
# environment) gets no failed server in `opencode mcp list`.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE/veris/.opencode-plugin" || exit 1
command -v node >/dev/null 2>&1 || { echo "node is not on PATH"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is not on PATH"; exit 1; }

fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

out="$(env -u VERIS_API_KEY node --input-type=module -e '
  const { default: plugin } = await import("./index.js");
  const hooks = await plugin();
  const cfg = {};
  await hooks.config(cfg);
  console.log(JSON.stringify({ commands: Object.keys(cfg.command ?? {}).sort(), mcp: cfg.mcp ?? null }));
' 2>&1)"; rc=$?
check "plugin loads and runs its config hook" 0 "$rc"
check "registers the three commands" '["veris:build","veris:fix","veris:setup"]' "$(printf '%s' "$out" | jq -c '.commands' 2>/dev/null)"
check "registers no MCP server" null "$(printf '%s' "$out" | jq -c '.mcp' 2>/dev/null)"

if [ "$fails" -eq 0 ]; then echo "opencode_plugin: all passed"; else echo "opencode_plugin: $fails failed"; exit 1; fi
