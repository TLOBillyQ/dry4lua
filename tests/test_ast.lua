local ast = require("dry4lua.ast")

local function parse(source)
  return ast.parse_source(source)
end

local function extract(source)
  return ast.extract_functions(parse(source))
end

-- parse / extract

test("ast: parses a minimal chunk", function()
  local chunk = parse("local x = 1")
  assert_eq(type(chunk), "table")
  assert_eq(#chunk, 1)
  assert_eq(chunk[1].tag, "Local")
end)

test("ast: extracts a named function", function()
  local funcs = extract("function foo()\nend")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "foo")
  assert_eq(funcs[1].start_line, 1)
  assert_eq(funcs[1].end_line, 2)
end)

test("ast: extracts a local function", function()
  local funcs = extract("local function helper() end")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "helper")
end)

test("ast: extracts dotted and method names", function()
  local dotted = extract("function a.b.c() end")[1]
  assert_eq(dotted.name, "a.b.c")
  local method = extract("function a.b:c() end")[1]
  assert_eq(method.name, "a.b.c")
end)

test("ast: anonymous functions are labeled by line", function()
  local funcs = extract("local f = function()\nend")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "anonymous@1")
end)

test("ast: nested functions are both extracted", function()
  local funcs = extract("function outer()\n  function inner()\n  end\nend")
  assert_eq(#funcs, 2)
  -- AST traversal discovers the outer function before descending into its body,
  -- so the parent appears first. This differs from the old token-stack order.
  assert_eq(funcs[1].name, "outer")
  assert_eq(funcs[1].start_line, 1)
  assert_eq(funcs[1].end_line, 4)
  assert_eq(funcs[2].name, "inner")
  assert_eq(funcs[2].start_line, 2)
  assert_eq(funcs[2].end_line, 3)
end)

test("ast: local f = function() end stays anonymous", function()
  local funcs = extract("local f = function() end")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "anonymous@1")
end)

test("ast: Set assignment to a function takes the target name", function()
  local funcs = extract("f = function() end")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "f")
end)

test("ast: anonymous function passed as argument", function()
  local funcs = extract("print(function() end)")
  assert_eq(#funcs, 1)
  assert_eq(funcs[1].name, "anonymous@1")
end)

-- normalization

test("ast: identifiers collapse to ident", function()
  local chunk = parse("function f()\n  local x = y\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  assert_true(serialized:find("(ident)", 1, true) ~= nil, "ident present")
  assert_true(serialized:find("x", 1, true) == nil, "name x removed")
  assert_true(serialized:find("y", 1, true) == nil, "name y removed")
end)

test("ast: literals collapse to literal/kind", function()
  local chunk = parse("function f()\n  local a = 1\n  local b = 's'\n  local c = true\n  local d = false\n  local e = nil\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  assert_true(serialized:find("(literal/number)", 1, true) ~= nil, "number literal")
  assert_true(serialized:find("(literal/string)", 1, true) ~= nil, "string literal")
  assert_true(serialized:find("(literal/boolean)", 1, true) ~= nil, "boolean literal")
  assert_true(serialized:find("(literal/nil)", 1, true) ~= nil, "nil literal")
  assert_true(serialized:find("'s'", 1, true) == nil, "string value removed")
end)

test("ast: operator stays in the tag", function()
  local chunk = parse("function f()\n  return a + b - c\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  assert_true(serialized:find("(op/add", 1, true) ~= nil, "add operator")
  assert_true(serialized:find("(op/sub", 1, true) ~= nil, "sub operator")
end)

test("ast: call callee is anonymized", function()
  local chunk = parse("function f()\n  print(1, 2)\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  assert_true(serialized:find("(Call (callee)", 1, true) ~= nil, "callee placeholder")
  assert_true(serialized:find("print", 1, true) == nil, "callee name removed")
end)

test("ast: keyword tags stay unchanged", function()
  local chunk = parse("function f()\n  if x then\n    return 1\n  end\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local serialized = ast.serialize(normalized)
  assert_true(serialized:find("(If ", 1, true) ~= nil, "If tag")
  assert_true(serialized:find("(Return ", 1, true) ~= nil, "Return tag")
end)

-- fingerprinting

test("ast: fingerprint set contains every normalized subtree", function()
  local chunk = parse("function f()\n  return a + b\nend")
  local func = ast.extract_functions(chunk)[1]
  local normalized = ast.normalize_node(func.node)
  local fps, count = ast.build_fingerprints(normalized)
  assert_true(count > 0, "non-empty fingerprint set")
  assert_true(fps[ast.serialize(normalized)], "root subtree present")
end)

test("ast: identical functions produce identical fingerprint sets", function()
  local a = ast.normalize_node(extract("function f()\n  return 1\nend")[1].node)
  local b = ast.normalize_node(extract("function g()\n  return 2\nend")[1].node)
  local fps_a, count_a = ast.build_fingerprints(a)
  local fps_b, count_b = ast.build_fingerprints(b)
  assert_eq(count_a, count_b)
  for key in pairs(fps_a) do
    assert_true(fps_b[key], "matching key: " .. key)
  end
end)

test("ast: node count includes all tagged AST nodes", function()
  local func = extract("function f(a)\n  local x = 1\nend")[1]
  local count = ast.count_nodes(func.node)
  assert_true(count >= 5, "at least a handful of nodes")
end)
