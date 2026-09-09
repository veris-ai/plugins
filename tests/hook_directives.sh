#!/usr/bin/env sh
# The UserPromptSubmit hook is the plugin's only imperative channel, and it
# fails silently: malformed JSON, a misplaced additionalContext or a missing
# hookEventName are all read as "no context" with no error anywhere. So the
# shape is checked here rather than discovered in a session.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="${VERIS_HOOKS:-$HERE/veris/hooks}"

fails=0
check() { # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'ok    %s\n' "$1"
  else printf 'FAIL  %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

check "hooks.json is where the plugin loader looks" 1 "$([ -f "$HOOKS/hooks.json" ] && echo 1 || echo 0)"
check "hooks.json is valid JSON" 0 "$(jq -e . "$HOOKS/hooks.json" >/dev/null 2>&1; echo $?)"
check "one UserPromptSubmit entry" 1 "$(jq '.hooks.UserPromptSubmit | length' "$HOOKS/hooks.json")"
check "type is command" command "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].type' "$HOOKS/hooks.json")"
check "command resolves through CLAUDE_PLUGIN_ROOT" 1 \
  "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$HOOKS/hooks.json" | grep -c '\${CLAUDE_PLUGIN_ROOT}')"

OUT="$(printf '{"hook_event_name":"UserPromptSubmit","user_prompt":"anything"}' | sh "$HOOKS/veris-directives.sh" 2>/dev/null)"
rc=$?
check "the script exits 0" 0 "$rc"
check "its stdout is one JSON object" 0 "$(printf '%s' "$OUT" | jq -e 'type == "object"' >/dev/null 2>&1; echo $?)"
check "hookEventName is UserPromptSubmit" UserPromptSubmit \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')"
# additionalContext nested in hookSpecificOutput: at the top level it is ignored
# without an error, which is the failure this file exists to prevent.
check "additionalContext is nested, not top-level" 1 \
  "$(printf '%s' "$OUT" | jq -r 'if (.hookSpecificOutput.additionalContext | type) == "string" and .additionalContext == null then 1 else 0 end')"

CTX="$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')"
LINES="$(printf '%s\n' "$CTX" | wc -l | tr -d ' ')"
check "under twelve lines: this rides every prompt of every session" 1 \
  "$([ "$LINES" -le 12 ] && echo 1 || echo 0)"

# The four imperatives. Each one is here because its absence lost a graded
# outcome; a rewrite that drops one should fail loudly.
for want in 'make that failure happen' 'default path' 'receipt' 'measured false'; do
  check "carries: $want" 1 "$(printf '%s' "$CTX" | grep -c "$want")"
done

# Agent-facing text says nothing about how the directive is being evaluated.
for deny in benchmark arm experiment treatment control; do
  check "says nothing about '$deny'" 0 "$(printf '%s' "$CTX" | grep -ci "$deny")"
done

if [ "$fails" -eq 0 ]; then echo "hook_directives: all passed"; else echo "hook_directives: $fails failed"; exit 1; fi
