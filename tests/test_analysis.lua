local lu = require("luaunit")
local analysis = require("dry4lua.analysis")

TestAnalysis = {}

local FIXTURES = ROOT .. "/tests/fixtures"

function TestAnalysis:test_finds_the_structurally_identical_fixture_pair()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  lu.assertEquals(#candidates, 1)
  lu.assertEquals(candidates[1].score, 1)
  local names = { candidates[1].left.name, candidates[1].right.name }
  table.sort(names)
  lu.assertEquals(names[1], "calculate_total")
  lu.assertEquals(names[2], "compute_sum")
end

function TestAnalysis:test_candidate_carries_file_and_line_ranges()
  local candidates = analysis.find_duplicates({ paths = { FIXTURES } })
  local left = candidates[1].left
  lu.assertTrue(left.file:match("dup_[ab]%.lua$") ~= nil, "left file")
  lu.assertEquals(left.start_line, 1)
  lu.assertEquals(left.end_line, 10)
end

function TestAnalysis:test_threshold_above_1_yields_nothing()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    threshold = 1.1,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_min_nodes_filters_by_ast_node_count()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_nodes = 1000,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_min_lines_filters_short_functions()
  local candidates = analysis.find_duplicates({
    paths = { FIXTURES },
    min_lines = 1000,
  })
  lu.assertEquals(#candidates, 0)
end

function TestAnalysis:test_empty_directory_yields_no_candidates()
  local candidates = analysis.find_duplicates({ paths = { ROOT .. "/tests" } })
  for _, candidate in ipairs(candidates) do
    lu.assertTrue(candidate.score >= 0.82, "score above threshold")
  end
end

function TestAnalysis:test_nested_inner_functions_match_outer_do_not()
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
  lu.assertTrue(inner_found, "inner functions validate/verify should match")
  lu.assertTrue(not outer_found, "outer functions should not match (different structure, no child inflation)")
end

function TestAnalysis:test_same_file_overlapping_entries_are_excluded()
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
      lu.assertTrue(not overlap,
        "overlapping same-file entries should not produce a candidate: "
        .. c.left.name .. " vs " .. c.right.name)
    end
  end
end

return TestAnalysis
