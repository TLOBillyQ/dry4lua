#!/bin/sh
# Run unit tests, verify CLI output matches the saved baseline, syntax-check sources.
# Usage: sh tests/check.sh   (must be run from the repository root)
set -e

LUADIR=${LUADIR:-/opt/homebrew/opt/lua@5.4/bin}
LUA=${LUA:-$LUADIR/lua5.4}
LUAC=${LUAC:-$LUADIR/luac5.4}
LUACHECK_DIR=${LUACHECK_DIR:-/opt/homebrew/Cellar/luacheck/1.2.0_1/libexec/share/lua/5.4}

if [ -d "$LUACHECK_DIR" ]; then
  LUA_PATH="$LUACHECK_DIR/?.lua;$LUACHECK_DIR/?/init.lua;$($LUA -e 'print(package.path)')"
  export LUA_PATH
fi

$LUA tests/run.lua

TEXT_OUT=$(mktemp)
JSON_OUT=$(mktemp)
trap 'rm -f "$TEXT_OUT" "$JSON_OUT"' EXIT

$LUA bin/dry4lua tests/corpus tests/fixtures > "$TEXT_OUT"
$LUA bin/dry4lua --json tests/corpus tests/fixtures > "$JSON_OUT"
diff tests/baseline/text.out "$TEXT_OUT"
diff tests/baseline/json.out "$JSON_OUT"

$LUAC -p lib/dry4lua/*.lua bin/dry4lua tests/*.lua tests/fixtures/*.lua tests/corpus/*.lua

echo "CHECK OK"
