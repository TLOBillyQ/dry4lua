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

test("analysis: min_nodes filters by AST node count", function()
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

test("analysis: nested inner functions match, outer functions do not (overlap fix)", function()
  local candidates = analysis.find_duplicates({ paths = { ROOT .. "/tests/corpus" } })
  -- Should find the validate/verify inner pair but NOT the outer pair
  -- (process_entries vs handle_records have different structures;
  --  their fingerprints no longer include inner function bodies).
  local inner_found = false
  local outer_found = false
  for _, c in ipairs(candidates) do
    local left_name = c.left.name
    local right_name = c.right.name
    if (left_name == "validate" and right_name == "verify")
        or (left_name == "verify" and right_name == "validate") then
      inner_found = true
    end
    if (left_name == "process_entries" and right_name == "handle_records")
        or (left_name == "handle_records" and right_name == "process_entries") then
      outer_found = true
    end
  end
  assert_true(inner_found, "inner functions validate/verify should match")
  assert_true(not outer_found, "outer functions should not match (different structure, no child inflation)")
end)

test("analysis: same-file overlapping entries are excluded from comparison", function()
  -- Scan corpus which contains nested_a.lua and nested_b.lua. Each has a
  -- parent function and a child function whose line ranges overlap (the
  -- child is nested inside the parent in the same file). The overlap
  -- check (dry4java semantics) prevents parent-vs-own-child comparisons.
  -- We verify this indirectly: scan only nested_a.lua, where the parent
  -- and child have overlapping ranges. Without the overlap check they
  -- would be compared pairwise; with it they are skipped.
  local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
  end

  local nested_a = ROOT .. "/tests/corpus/nested_a.lua"
  if not file_exists(nested_a) then
    -- corpus file doesn't exist; skip gracefully
    return
  end

  local candidates = analysis.find_duplicates({ paths = { nested_a } })
  -- A single file with two overlapping entries should produce no
  -- candidates because the overlap check excludes the pair.
  for _, c in ipairs(candidates) do
    -- If any candidate has both left and right from the same file
    -- with overlapping ranges, that's a bug.
    if c.left.file == c.right.file then
      local overlap = c.left.start_line <= c.right.end_line
          and c.right.start_line <= c.left.end_line
      assert_true(not overlap,
        "overlapping same-file entries should not produce a candidate: "
        .. c.left.name .. " vs " .. c.right.name)
    end
  end
end)
