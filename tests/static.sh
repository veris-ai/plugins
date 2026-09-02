#!/usr/bin/env sh
# Static checks on the shipped plugin. No network, no sandbox, no agent.
#
# The checks PR #20 ran by hand and never committed are here, plus the ones
# added with the proof scripts. Run from the repository root:
#
#   sh tests/static.sh
#
# Exit: 0 all green · 1 at least one check failed.
set -u

PASS=0
FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL + 1)); }
head_() { printf '\n%s\n' "$1"; }

SKILLS='veris-sim/skills'
[ -d "$SKILLS" ] || { echo "run from the repository root" >&2; exit 1; }

# Every markdown file the plugin ships.
MD="$(find "$SKILLS" -name '*.md' | sort)"
SH="$(find "$SKILLS" -name '*.sh' | sort) $(find tests -name '*.sh' 2>/dev/null | sort)"

# --------------------------------------------------------- the client surface

head_ 'Client surface — nothing internal reaches a shipped instruction'

# Names that exist only inside Veris' own repositories. An instruction naming one
# cannot be executed by someone who has installed the plugin.
INTERNAL='veris-benchmark-harness|services-sandbox|\.plugin-stage|sbs-|studies/|runs/[a-z]|harness/|GRADING\.md|arm-skills|integration-testing|discovering-vendor-behavior|setting-up-veris'
hits="$(grep -nE "$INTERNAL" $MD 2>/dev/null || true)"
if [ -n "$hits" ]; then bad "internal references under $SKILLS:"; printf '%s\n' "$hits" | sed 's/^/       /'
else ok 'no internal repository names, paths or removed skill names'; fi

# /veris/operations was removed at 0.6.4 and deliberately restored at 0.6.8
# (9542baa, "the coverage catalogue is the first door"). The check that forbade
# it went with it; twin.md and troubleshooting.md now carry the calibrated rule.

# A refusal code is one service's, not a universal contract. 501 may be
# discussed only where the calibrated rule lives.
hits="$(grep -ln '501' $MD 2>/dev/null | grep -v 'troubleshooting.md' || true)"
if [ -n "$hits" ]; then bad "a refusal code appears outside troubleshooting.md: $hits"
else ok 'no universal refusal code outside the calibrated rule'; fi

# A platform is measured by the session, never named by a skill. The one file
# that may name one is the dated record of what each platform measured as.
PLATFORMS='daytona|e2b'
hits="$(grep -nwiE "$PLATFORMS" $MD 2>/dev/null | grep -v "^$SKILLS/setup/reference/platforms.md:" || true)"
if [ -n "$hits" ]; then bad "a platform is named outside setup/reference/platforms.md:"; printf '%s\n' "$hits" | sed 's/^/       /'
else ok 'no platform name outside setup/reference/platforms.md'; fi

# ------------------------------------------------------------------- linking

head_ 'Links and references'

broken=''
for f in $MD; do
  dir="$(dirname "$f")"
  # [text](target) where target is relative and not a fragment or URL
  for target in $(grep -oE '\]\([^)#][^)]*\)' "$f" 2>/dev/null | sed 's/^](//;s/)$//' | grep -vE '^(https?|mailto):' || true); do
    case "$target" in *'#'*) target="${target%%#*}" ;; esac
    [ -n "$target" ] || continue
    [ -e "$dir/$target" ] || broken="$broken
  $f -> $target"
  done
done
if [ -n "$broken" ]; then bad "unresolved relative links:$broken"
else ok 'every relative markdown link resolves'; fi

# The check that would have caught .veris/MEASUREMENTS.md: an artifact named in
# an instruction that nothing in the plugin creates or defines.
ARTIFACTS='setup.json NOTES.md run.sh ca bin tasks session.md'
unknown=''
for a in $(grep -ohE '\.veris/[A-Za-z0-9_.<>/-]+' $MD 2>/dev/null | sed 's|^\.veris/||' | cut -d/ -f1 | sort -u); do
  case " $ARTIFACTS " in *" $a "*) ;; *) unknown="$unknown $a" ;; esac
done
if [ -n "$unknown" ]; then bad "instructions name .veris artifacts nothing creates:$unknown"
else ok 'every .veris artifact named in an instruction is one the plugin creates'; fi

# ---------------------------------------------------------------- frontmatter

head_ 'Frontmatter'

for f in $(find "$SKILLS" -name 'SKILL.md' | sort); do
  d="$(basename "$(dirname "$f")")"
  [ "$(head -1 "$f")" = '---' ] || { bad "$f does not open with frontmatter"; continue; }
  name="$(sed -n '2,/^---$/p' "$f" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  desc="$(sed -n '2,/^---$/p' "$f" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
  err=''
  [ "$name" = "$d" ] || err="$err name '$name' != directory '$d';"
  printf '%s' "$name" | grep -qE '^[a-z0-9-]{1,64}$' || err="$err name is not 1-64 lowercase/digits/hyphens;"
  printf '%s' "$name" | grep -qiE 'anthropic|claude' && err="$err name uses a reserved word;"
  [ -n "$desc" ] || err="$err description is empty;"
  [ "${#desc}" -le 1024 ] || err="$err description exceeds 1024 characters;"
  printf '%s%s' "$name" "$desc" | grep -q '<' && err="$err frontmatter contains an XML-ish tag;"
  if [ -n "$err" ]; then bad "$f:$err"; else ok "$f frontmatter"; fi
done

# ---------------------------------------------------------------------- gates

head_ 'Gate numbering is contiguous'

gated="$(grep -l '^## Gate [0-9]' $(find "$SKILLS" -name 'SKILL.md') 2>/dev/null | sort)"
[ -n "$gated" ] || bad 'no skill declares a gate'
for f in $gated; do
  nums="$(grep -oE '^## Gate [0-9]+' "$f" | grep -oE '[0-9]+' | sort -n | uniq)"
  [ -n "$nums" ] || { bad "$f declares no gates"; continue; }
  expected=''; i="$(printf '%s\n' "$nums" | head -1)"
  for n in $nums; do
    if [ "$n" != "$i" ]; then expected="gap before Gate $n"; break; fi
    i=$((i + 1))
  done
  if [ -n "$expected" ]; then bad "$f: $expected"
  else ok "$f gates $(printf '%s' "$nums" | tr '\n' ' ')"; fi
done

# --------------------------------------------------------------------- curl

head_ 'Examples fail visibly'

# Only inside fenced code blocks: an example is something a reader can run.
# Prose that mentions curl is not an invocation.
hits="$(for f in $MD; do
  awk -v F="$f" '
    /^[[:space:]]*```/ { infence = !infence; next }
    infence && /^[[:space:]]*curl / && !/--fail-with-body/ { printf "  %s:%d: %s\n", F, NR, $0 }
  ' "$f"
done)"
if [ -n "$hits" ]; then bad "curl without --fail-with-body — an HTTP error would arrive as empty evidence:"; printf '%s\n' "$hits"
else ok 'every curl example fails visibly'; fi

# ------------------------------------------------------------------- packaging

head_ 'Packaging'

v_claude="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' veris-sim/.claude-plugin/plugin.json | head -1)"
v_codex="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' veris-sim/.codex-plugin/plugin.json | head -1)"
v_market="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .claude-plugin/marketplace.json | head -1)"
v_open="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' veris-sim/.opencode-plugin/package.json | head -1)"
if [ "$v_claude" = "$v_codex" ] && [ "$v_claude" = "$v_market" ] && [ "$v_claude" = "$v_open" ]; then
  ok "all four manifests read $v_claude"
else
  bad "manifest versions disagree: claude=$v_claude codex=$v_codex marketplace=$v_market opencode=$v_open"
fi

# setup's SKILL.md carries the running version as a literal, because a staged
# script cannot know it. That literal has to track the manifests or the staleness
# check reports drift that is not there.
lit="$(grep -o -- '--plugin-version [0-9][^ `]*' "$SKILLS/setup/SKILL.md" | head -1 | awk '{print $2}')"
if [ -z "$lit" ]; then
  bad 'setup/SKILL.md names no --plugin-version literal'
elif [ "$lit" = "$v_claude" ]; then
  ok "setup/SKILL.md --plugin-version matches the manifests ($lit)"
else
  bad "setup/SKILL.md says --plugin-version $lit, manifests read $v_claude"
fi

# .opencode-plugin/skills/ is prepack output. Tracking it means hand edits that
# the next publish silently discards.
if git ls-files --error-unmatch veris-sim/.opencode-plugin/skills >/dev/null 2>&1; then
  bad '.opencode-plugin/skills/ is tracked; it is generated by prepack'
else
  ok '.opencode-plugin/skills/ is prepack output, not tracked'
fi

# index.js registers the skills twice over: COMMANDS an engineer can type,
# SKILL_PATHS the model can load. Neither may drift from the directories.
IDX='veris-sim/.opencode-plugin/index.js'
arr() { sed -n "s/^const $1 = \[\(.*\)\].*/\1/p" "$IDX" | tr -d '" ' | tr ',' '\n' | grep -v '^$' | sort; }
commands="$(arr COMMANDS)"; paths="$(arr SKILL_PATHS)"
dirs="$(find "$SKILLS" -mindepth 1 -maxdepth 1 -type d ! -name veris-reference -exec basename {} \; | sort)"
if [ -z "$paths" ]; then bad "$IDX declares no SKILL_PATHS array"
elif [ "$paths" = "$dirs" ]; then ok "index.js SKILL_PATHS = the skill directories: $(printf '%s' "$dirs" | tr '\n' ' ')"
else bad "index.js SKILL_PATHS ($(printf '%s' "$paths" | tr '\n' ' ')) != skill directories less veris-reference ($(printf '%s' "$dirs" | tr '\n' ' '))"; fi
stray=''
for c in $commands; do printf '%s\n' "$paths" | grep -qx "$c" || stray="$stray $c"; done
if [ -z "$commands" ]; then bad "$IDX declares no COMMANDS array"
elif [ -n "$stray" ]; then bad "index.js COMMANDS not in SKILL_PATHS:$stray"
else ok 'index.js COMMANDS is a subset of SKILL_PATHS'; fi
for n in $paths; do
  fm="$(sed -n '2,/^---$/p' "$SKILLS/$n/SKILL.md" 2>/dev/null | sed -n 's/^name:[[:space:]]*//p' | head -1)"
  if [ "$fm" = "$n" ]; then ok "index.js registers '$n' and its frontmatter agrees"
  else bad "index.js registers '$n' but $SKILLS/$n/SKILL.md names '$fm'"; fi
done

# The transport is the session's to measure, not a manifest's to advertise.
MANIFESTS='veris-sim/.opencode-plugin/package.json veris-sim/.claude-plugin/plugin.json veris-sim/.codex-plugin/plugin.json .claude-plugin/marketplace.json'
hits="$(grep -n '"description"' $MANIFESTS | grep -E 'through `?veris-proxy' || true)"
tbl="$(grep -nE '^\| ' README.md veris-sim/.opencode-plugin/README.md | grep -E 'through `?veris-proxy' || true)"
if [ -n "$hits$tbl" ]; then bad 'a manifest description or README command table advertises the transport:'; printf '%s\n%s\n' "$hits" "$tbl" | sed '/^$/d;s/^/       /'
else ok 'no manifest description or README command table says "through veris-proxy"'; fi

for d in $(find "$SKILLS" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort); do
  f="$SKILLS/$d/agents/openai.yaml"
  if [ ! -f "$f" ]; then bad "$f is missing — every skill ships its interface block"
  elif grep -q 'display_name' "$f"; then ok "$f intact"
  else bad "$f lost its interface block"; fi
done

# --------------------------------------------------------------------- shell

head_ 'Shell syntax'

for f in $SH; do
  [ -f "$f" ] || continue
  if sh -n "$f" 2>/dev/null; then ok "sh -n $f"; else bad "sh -n $f"; fi
done

# -------------------------------------------------------------------- verdict

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
