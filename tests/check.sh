#!/bin/sh
# Run unit tests, verify CLI output matches the saved baseline, syntax-check sources.
# Usage: sh tests/check.sh   (must be run from the repository root)
set -e

LUADIR=${LUADIR:-/opt/homebrew/opt/lua@5.4/bin}
LUA=${LUA:-$LUADIR/lua5.4}
LUAC=${LUAC:-$LUADIR/luac5.4}

$LUA tests/run.lua

TEXT_OUT=$(mktemp)
JSON_OUT=$(mktemp)
trap 'rm -f "$TEXT_OUT" "$JSON_OUT"' EXIT

$LUA tools/quality/dry.lua tests/corpus tests/fixtures > "$TEXT_OUT"
$LUA tools/quality/dry.lua --json tests/corpus tests/fixtures > "$JSON_OUT"
diff tests/baseline/text.out "$TEXT_OUT"
diff tests/baseline/json.out "$JSON_OUT"

$LUAC -p lib/dry4lua/*.lua tools/quality/dry.lua tests/*.lua tests/fixtures/*.lua tests/corpus/*.lua

echo "CHECK OK"
