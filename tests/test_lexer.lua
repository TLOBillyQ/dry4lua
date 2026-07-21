local lexer = require("dry4lua.lexer")

local function kinds(source)
  local result = {}
  for _, tok in ipairs(lexer.tokenize(source)) do
    result[#result + 1] = tok.type .. ":" .. tok.value
  end
  return result
end

local function concat(list)
  return table.concat(list, "|")
end

test("lexer: keywords, identifiers, symbols, numbers", function()
  assert_eq(
    concat(kinds("local x = 42")),
    "keyword:local|identifier:x|symbol:=|number:42"
  )
end)

test("lexer: keyword set is exact", function()
  assert_eq(concat(kinds("localx")), "identifier:localx")
  assert_eq(concat(kinds("end")), "keyword:end")
  assert_eq(concat(kinds("_private")), "identifier:_private")
end)

test("lexer: numeric literal forms", function()
  assert_eq(concat(kinds("0x1F")), "number:0x1F")
  assert_eq(concat(kinds("3.14")), "number:3.14")
  assert_eq(concat(kinds("1e10")), "number:1e10")
  assert_eq(concat(kinds("1E-2")), "number:1E-2")
  assert_eq(concat(kinds("0b101")), "number:0b101")
  assert_eq(concat(kinds("0xA.8p1")), "number:0xA.8p1")
end)

test("lexer: digit followed by x is not hex without leading zero", function()
  assert_eq(concat(kinds("1x")), "number:1|identifier:x")
  assert_eq(concat(kinds("2b")), "number:2|identifier:b")
end)

test("lexer: number followed by concat operator", function()
  assert_eq(concat(kinds("1..2")), "number:1|symbol:..|number:2")
end)

test("lexer: quoted strings with escapes", function()
  assert_eq(concat(kinds('"a\\"b"')), 'string:"a\\"b"')
  assert_eq(concat(kinds("'it\\'s'")), "string:'it\\'s'")
end)

test("lexer: long bracket strings", function()
  assert_eq(concat(kinds("[[hello]]")), "string:[[hello]]")
  assert_eq(concat(kinds("[==[a]b]==]")), "string:[==[a]b]==]")
end)

test("lexer: long string spanning lines advances line count", function()
  local tokens = lexer.tokenize("[[a\nb]]\nx")
  assert_eq(tokens[1].line, 1)
  assert_eq(tokens[2].line, 3)
  assert_eq(tokens[2].value, "x")
end)

test("lexer: line comments are skipped", function()
  assert_eq(concat(kinds("a -- trailing\nb")), "identifier:a|identifier:b")
end)

test("lexer: block comments are skipped and counted", function()
  local tokens = lexer.tokenize("--[[\nignored\n]]\ny")
  assert_eq(#tokens, 1)
  assert_eq(tokens[1].value, "y")
  assert_eq(tokens[1].line, 4)
end)

test("lexer: multi-character symbols", function()
  assert_eq(
    concat(kinds("a == b ~= c <= d >= e .. f ...")),
    "identifier:a|symbol:==|identifier:b|symbol:~=|identifier:c"
    .. "|symbol:<=|identifier:d|symbol:>=|identifier:e|symbol:.."
    .. "|identifier:f|symbol:..."
  )
end)

test("lexer: CRLF is normalized", function()
  local tokens = lexer.tokenize("a\r\nb")
  assert_eq(tokens[2].value, "b")
  assert_eq(tokens[2].line, 2)
end)

test("lexer: token positions", function()
  local tokens = lexer.tokenize("ab = 12")
  assert_eq(tokens[1].start_pos, 1)
  assert_eq(tokens[1].end_pos, 2)
  assert_eq(tokens[3].start_pos, 6)
  assert_eq(tokens[3].end_pos, 7)
end)

test("lexer: empty and nil input", function()
  assert_eq(#lexer.tokenize(""), 0)
  assert_eq(#lexer.tokenize(nil), 0)
end)
