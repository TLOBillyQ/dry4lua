local lu = require("luaunit")
local ast = require("dry4lua.ast")

TestAst = {}

local function parse(source)
  return ast.parse_source(source)
end

local function extract(source)
  return ast.extract_functions(parse(source))
end

-- parse / extract

function TestAst:test_parses_a_minimal_chunk()
  local chunk = parse("local x = 1")
  lu.assertEquals(type(chunk), "table")
  lu.assertEquals(#chunk, 1)
  lu.assertEquals(chunk[1].tag, "Local")
end

function TestAst:test_extracts_a_named_function()
  local funcs = extract("function foo()\nend")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "foo")
  lu.assertEquals(funcs[1].start_line, 1)
  lu.assertEquals(funcs[1].end_line, 2)
end

function TestAst:test_extracts_a_local_function()
  local funcs = extract("local function helper() end")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "helper")
end

function TestAst:test_extracts_dotted_and_method_names()
  local dotted = extract("function a.b.c() end")[1]
  lu.assertEquals(dotted.name, "a.b.c")
  local method = extract("function a.b:c() end")[1]
  lu.assertEquals(method.name, "a.b.c")
end

function TestAst:test_anonymous_functions_are_labeled_by_line()
  local funcs = extract("local f = function()\nend")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "anonymous@1")
end

function TestAst:test_nested_functions_are_both_extracted()
  local funcs = extract("function outer()\n  function inner()\n  end\nend")
  lu.assertEquals(#funcs, 2)
  -- AST traversal discovers the outer function before descending into its body,
  -- so the parent appears first. This differs from the old token-stack order.
  lu.assertEquals(funcs[1].name, "outer")
  lu.assertEquals(funcs[1].start_line, 1)
  lu.assertEquals(funcs[1].end_line, 4)
  lu.assertEquals(funcs[2].name, "inner")
  lu.assertEquals(funcs[2].start_line, 2)
  lu.assertEquals(funcs[2].end_line, 3)
end

function TestAst:test_local_function_assignment_stays_anonymous()
  local funcs = extract("local f = function() end")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "anonymous@1")
end

function TestAst:test_set_assignment_takes_target_name()
  local funcs = extract("f = function() end")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "f")
end

function TestAst:test_anonymous_function_passed_as_argument()
  local funcs = extract("print(function() end)")
  lu.assertEquals(#funcs, 1)
  lu.assertEquals(funcs[1].name, "anonymous@1")
end

-- normalization

function TestAst:test_identifiers_collapse_to_ident()
  local chunk = parse("function f()\n  local x = y\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  lu.assertTrue(serialized:find("(ident)", 1, true) ~= nil, "ident present")
  lu.assertTrue(serialized:find("x", 1, true) == nil, "name x removed")
  lu.assertTrue(serialized:find("y", 1, true) == nil, "name y removed")
end

function TestAst:test_literals_collapse_to_literal_kind()
  local chunk = parse("function f()\n  local a = 1\n  local b = 's'\n  local c = true\n  local d = false\n  local e = nil\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  lu.assertTrue(serialized:find("(literal/number)", 1, true) ~= nil, "number literal")
  lu.assertTrue(serialized:find("(literal/string)", 1, true) ~= nil, "string literal")
  lu.assertTrue(serialized:find("(literal/boolean)", 1, true) ~= nil, "boolean literal")
  lu.assertTrue(serialized:find("(literal/nil)", 1, true) ~= nil, "nil literal")
  lu.assertTrue(serialized:find("'s'", 1, true) == nil, "string value removed")
end

function TestAst:test_operator_stays_in_the_tag()
  local chunk = parse("function f()\n  return a + b - c\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  lu.assertTrue(serialized:find("(op/add", 1, true) ~= nil, "add operator")
  lu.assertTrue(serialized:find("(op/sub", 1, true) ~= nil, "sub operator")
end

function TestAst:test_call_callee_is_anonymized()
  local chunk = parse("function f()\n  print(1, 2)\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  lu.assertTrue(serialized:find("(Call (callee)", 1, true) ~= nil, "callee placeholder")
  lu.assertTrue(serialized:find("print", 1, true) == nil, "callee name removed")
end

function TestAst:test_keyword_tags_stay_unchanged()
  local chunk = parse("function f()\n  if x then\n    return 1\n  end\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  lu.assertTrue(serialized:find("(If ", 1, true) ~= nil, "If tag")
  lu.assertTrue(serialized:find("(Return ", 1, true) ~= nil, "Return tag")
end

-- fingerprinting

function TestAst:test_fingerprint_set_contains_every_normalized_subtree()
  local chunk = parse("function f()\n  return a + b\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local fps, count = ast.build_fingerprints(normalized)
  lu.assertTrue(count > 0, "non-empty fingerprint set")
  lu.assertTrue(fps[ast.serialize(normalized)], "root subtree present")
end

function TestAst:test_identical_functions_produce_identical_fingerprint_sets()
  local a = ast.normalize_node(extract("function f()\n  return 1\nend")[1].node)
  local b = ast.normalize_node(extract("function g()\n  return 2\nend")[1].node)
  local fps_a, count_a = ast.build_fingerprints(a)
  local fps_b, count_b = ast.build_fingerprints(b)
  lu.assertEquals(count_a, count_b)
  for key in pairs(fps_a) do
    lu.assertTrue(fps_b[key], "matching key: " .. key)
  end
end

function TestAst:test_nested_function_nodes_collapse_in_parent_normalization()
  local chunk = parse("function outer()\n  function inner()\n    return 1\n  end\n  local x = inner()\nend")
  local funcs = ast.extract_functions(chunk)
  lu.assertEquals(#funcs, 2)
  -- Normalize the outer function's node. Nested Function nodes inside
  -- should be collapsed to (function) leaves so that the outer
  -- function's fingerprints do not include the inner function's body.
  local outer_normalized = ast.normalize_node(funcs[1].node)
  local outer_serialized = ast.serialize(outer_normalized)
  -- The outer has an (ident) for local x, a (function) leaf for the
  -- collapsed inner, a (Call (callee) (ident)) for inner(), and a
  -- (Local ...) wrapper. It must NOT contain a (Return because the
  -- only return belongs to the collapsed inner function.
  lu.assertTrue(outer_serialized:find("(function)", 1, true) ~= nil, "collapsed function leaf present")
  lu.assertTrue(outer_serialized:find("(Return", 1, true) == nil, "inner Return not present in parent")
  -- The inner function's own normalization should still contain its body.
  local inner_normalized = ast.normalize_node(funcs[2].node)
  local inner_serialized = ast.serialize(inner_normalized)
  lu.assertTrue(inner_serialized:find("(Return", 1, true) ~= nil, "inner Return present in own normalization")
end

function TestAst:test_node_count_includes_all_tagged_nodes()
  local func = extract("function f(a)\n  local x = 1\nend")[1]
  local count = ast.count_nodes(func.node)
  lu.assertTrue(count >= 5, "at least a handful of nodes")
end

return TestAst
