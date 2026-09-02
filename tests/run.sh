#!/usr/bin/env sh
# The Stage-1 suite: everything that can be checked without an agent, a sandbox
# or a network. Run from the repository root before every commit.
#
#   sh tests/run.sh
set -u
cd "$(dirname "$0")/.." || exit 1

rc=0
printf '===== static =====\n'
sh tests/static.sh  || rc=1
printf '\n===== scripts =====\n'
sh tests/scripts.sh || rc=1
printf '\n===== integration =====\n'
sh tests/integration.sh || rc=1

printf '\n'
[ "$rc" -eq 0 ] && printf 'Stage 1: green\n' || printf 'Stage 1: RED\n'
exit "$rc"
