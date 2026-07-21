local analysis = require("dry4lua.analysis")

local FIXTURES = ROOT .. "/tests/fixtures"

test("analysis: finds the structurally identical fixture pair", function()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  assert_eq(#candidates, 1)
  assert_eq(candidates[1].score, 1)
  local names = { candidates[1].left.name, candidates[1].right.name }
  table.sort(names)
  assert_eq(names[1], "calculate_total")
  assert_eq(names[2], "compute_sum")
end)

test("analysis: candidate carries file and line ranges", function()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  local left = candidates[1].left
  assert_true(left.file:match("dup_[ab]%.lua$") ~= nil, "left file")
  assert_eq(left.start_line, 1)
  assert_eq(left.end_line, 10)
end)

test("analysis: threshold above 1 yields nothing", function()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    threshold = 1.1,
  })
  assert_eq(#candidates, 0)
end)

test("analysis: min_nodes filters small functions", function()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_nodes = 1000,
  })
  assert_eq(#candidates, 0)
end)

test("analysis: min_lines filters short functions", function()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_lines = 1000,
  })
  assert_eq(#candidates, 0)
end)

test("analysis: empty directory yields no candidates", function()
  local candidates = analysis.find_duplicates({ paths = { ROOT .. "/tests" } })
  for _, candidate in ipairs(candidates) do
    assert_true(candidate.score >= 0.82, "score above threshold")
  end
end)
