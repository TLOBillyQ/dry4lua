-- Minimal test runner for dry4lua. Usage: lua5.4 tests/run.lua
local script = arg[0] or "tests/run.lua"
ROOT = script:match("^(.+)/tests/run%.lua$") or "."
package.path = ROOT .. "/lib/?.lua;" .. package.path

local luacheck_dir = os.getenv("LUACHECK_DIR")
if luacheck_dir then
  package.path = luacheck_dir .. "/?.lua;" .. luacheck_dir .. "/?/init.lua;" .. package.path
end

local passed = 0
local failed = 0
local failures = {}

function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = name .. ": " .. tostring(err)
  end
end

function assert_eq(actual, expected, label)
  if actual ~= expected then
    error((label or "assert_eq")
      .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual), 2)
  end
end

function assert_true(value, label)
  if not value then
    error((label or "assert_true") .. ": expected truthy value", 2)
  end
end

local suites = {
  "tests/test_ast.lua",
  "tests/test_analysis.lua",
  "tests/test_cli.lua",
}
for _, suite in ipairs(suites) do
  dofile(ROOT .. "/" .. suite)
end

print(string.format("%d passed, %d failed", passed, failed))
for _, message in ipairs(failures) do
  print("FAIL " .. message)
end
os.exit(failed == 0 and 0 or 1)
