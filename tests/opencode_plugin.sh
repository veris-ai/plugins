#!/usr/bin/env sh
set -eu
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
# Install the locked adapter dependency first: npm ci --prefix veris/.opencode-plugin
node --test tests/opencode_plugin.test.mjs
