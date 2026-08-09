-- Benchmark: repeated find_duplicates over a fixed frozen input
-- (tests/corpus + tests/fixtures).
-- Usage: lua5.4 tests/bench.lua [iterations]   (run from the repository root)
local script = arg[0] or "tests/bench.lua"
local root = script:match("^(.+)/tests/bench%.lua$") or "."
package.path = root .. "/src/?.lua;" .. package.path

local analysis = require("dry4lua.analysis")

local n = tonumber(arg[1]) or 100
local options = { paths = { "tests/corpus", "tests/fixtures" } }

analysis.find_duplicates(options) -- warmup

local start = os.clock()
for _ = 1, n do
  analysis.find_duplicates(options)
end
local elapsed = os.clock() - start

io.write(string.format("iterations=%d total=%.3fs avg=%.3fms\n", n, elapsed, elapsed / n * 1000))
