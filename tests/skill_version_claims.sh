#!/usr/bin/env sh
# A skill document must not freeze a fact about a moving release into its prose.
#
# @veris-ai/daytona went 0.2.1 to 0.4.0 in four days, dropping its executable on
# the way. daytona.md had recorded "as checked on 2026-09-04, the latest release,
# 0.2.1, has no bin entry" and told the agent to stop unless a release exported
# that executable, so every release after the observation left the hosted tier
# unreachable rather than merely out of date. The recipes now resolve the release
# at task time and let npm's lockfile hold it for the run; these three rules fail
# a document that goes back to writing the answer down instead.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DOCS="${SKILL_DOCS:-$HERE/veris/skills}"  # override to check another copy

fails=0
# deny <name> <why> <matches...>  -- any match is a failure; no match passes.
deny() {
  name="$1"; why="$2"; shift 2
  if [ -n "$*" ]; then
    printf 'FAIL  %s: %s\n' "$name" "$why"
    printf '%s\n' "$*" | sed 's|^|      |'
    fails=$((fails + 1))
  else
    printf 'ok    %s\n' "$name"
  fi
}

# 1. A package specifier names a concrete version or a <version> placeholder.
#    Both make the reader guess which release the step means, and both outlive
#    the release they were written for. Ask for @latest and let --save-exact and
#    the lockfile hold what resolved.
deny "no pinned @veris-ai specifier" "use @latest with --save-exact and a lockfile" \
  "$(grep -rnE '@veris-ai/[A-Za-z0-9.-]+@' "$DOCS" \
     | grep -vE '@veris-ai/[A-Za-z0-9.-]+@latest')"

# 2. "latest is 0.1.1" resolves a moving tag and writes the answer down. It is
#    wrong from the next publish onward, and it reads as current because it is
#    stated as a fact rather than as a date-stamped reading. A minimum-version
#    floor ("needs at least 0.3.1; if latest is older, stop") is the opposite of
#    this and stays true, so only an assertion that latest EQUALS a version is
#    denied.
deny "no frozen 'latest' resolution" "resolve latest at task time, do not record what it resolved to" \
  "$(grep -rniE 'latest[^0-9]{0,20}(is|was|release,?)[^0-9]{0,4}[0-9]+\.[0-9]+\.[0-9]+' "$DOCS")"

# 3. The veris-daytona executable was removed in @veris-ai/daytona 0.4.0. Naming
#    a verb is an instruction to run a command that does not exist. Saying the
#    executable is gone is the documentation we want, so only the command form
#    is denied.
deny "no removed veris-daytona verbs" "the package ships no executable; use the SDK" \
  "$(grep -rnE 'veris-daytona[[:space:]]+(provision|push|exec|teardown|run)' "$DOCS")"

if [ "$fails" -eq 0 ]; then
  echo "skill_version_claims: all passed"
else
  echo "skill_version_claims: $fails failed"
  exit 1
fi
