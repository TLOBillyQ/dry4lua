local ast = {}

local ok_decoder, decoder = pcall(require, "luacheck.decoder")
local ok_parser, parser = pcall(require, "luacheck.parser")

if not ok_decoder or not ok_parser then
  error("luacheck required: luarocks install luacheck", 0)
end

function ast.parse_source(source)
  local ok, parsed = pcall(parser.parse, decoder.decode(source))
  if not ok then
    return nil, tostring(parsed)
  end
  if not parsed then
    return nil, "parse error"
  end
  return parsed
end

function ast.parse_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, "cannot open " .. path
  end
  local source = file:read("*a")
  file:close()
  return ast.parse_source(source)
end

local function is_identifier_node(node)
  return type(node) == "table" and node.tag == "Id"
end

local function is_index_node(node)
  return type(node) == "table" and node.tag == "Index"
end

local function target_name(target)
  if is_identifier_node(target) then
    return target[1]
  end
  if is_index_node(target) then
    local left = target_name(target[1])
    -- Field access stores the key as a String literal node.
    local right = (is_identifier_node(target[2]) or target[2].tag == "String") and target[2][1] or nil
    if left and right then
      return left .. "." .. right
    end
  end
  return nil
end

local function function_name(parent)
  if type(parent) ~= "table" then
    return nil
  end
  local tag = parent.tag
  local targets = parent[1]
  local exprs = parent[2]
  if tag ~= "Set" and tag ~= "Localrec" and tag ~= "Local" then
    return nil
  end
  if type(targets) ~= "table" or type(exprs) ~= "table" then
    return nil
  end
  if #targets ~= 1 or #exprs ~= 1 then
    return nil
  end
  if tag == "Local" then
    -- local f = function() end is a Local; keep it anonymous to match
    -- the syntactic distinction between local function f() (Localrec)
    -- and local f = function().
    return nil
  end
  return target_name(targets[1])
end

local function walk_functions(node, parent, grandparent, entries)
  if type(node) ~= "table" then
    return
  end
  if node.tag == "Function" then
    -- A named function declaration appears as the sole expression of a
    -- Set/Localrec statement. The Function node's parent is the expression
    -- array, so the statement itself is the grandparent.
    local name = function_name(grandparent) or ("anonymous@%d"):format(node.line or 0)
    local end_line = node.end_range and node.end_range.line or node.line or 0
    entries[#entries + 1] = {
      node = node,
      name = name,
      start_line = node.line or 0,
      end_line = end_line,
    }
  end
  for _, child in ipairs(node) do
    if type(child) == "table" then
      walk_functions(child, node, parent, entries)
    end
  end
end

function ast.extract_functions(chunk)
  local entries = {}
  for _, statement in ipairs(chunk) do
    walk_functions(statement, nil, nil, entries)
  end
  return entries
end

function ast.count_nodes(node)
  if type(node) ~= "table" then
    return 0
  end
  -- Count every tagged AST node in the subtree; tagless arrays are structural
  -- containers, not nodes.
  local count = node.tag and 1 or 0
  for _, child in ipairs(node) do
    count = count + ast.count_nodes(child)
  end
  return count
end

local LITERAL_KINDS = {
  Number = "number",
  String = "string",
  True = "boolean",
  False = "boolean",
  Nil = "nil",
}

local function normalized_tag(node)
  local kind = LITERAL_KINDS[node.tag]
  if kind then
    return "literal/" .. kind
  end
  if node.tag == "Op" then
    return "op/" .. tostring(node[1])
  end
  return node.tag
end

function ast.normalize_node(node, collapse_nested_functions)
  if type(node) ~= "table" then
    return node
  end

  -- When recursing into a function body, collapse nested Function nodes
  -- to a leaf so that parent-function fingerprints do not include
  -- child-function body details. This prevents double-reporting when
  -- both a parent pair and a child pair match the same similarity
  -- targets (the parent match would be a side-effect of the child's
  -- fingerprints, not the parent's own structure).
  if collapse_nested_functions and node.tag == "Function" then
    return { tag = "function" }
  end

  local tag = node.tag
  -- AST arrays (statement lists, expression lists, parameter lists) have no tag.
  if not tag then
    local normalized = {}
    for index = 1, #node do
      normalized[index] = ast.normalize_node(node[index], true)
    end
    return normalized
  end

  local normalized = { tag = normalized_tag(node) }

  if tag == "Id" then
    -- identifiers collapse to a leaf
    return { tag = "ident" }
  end

  if LITERAL_KINDS[tag] then
    -- literals collapse to a leaf
    return { tag = normalized.tag }
  end

  if tag == "Op" then
    -- operator string becomes part of the tag; operands remain
    for index = 2, #node do
      normalized[index - 1] = ast.normalize_node(node[index], true)
    end
    return normalized
  end

  if tag == "Call" then
    -- callee expression is anonymized; arguments stay
    normalized[1] = { tag = "callee" }
    for index = 2, #node do
      normalized[index] = ast.normalize_node(node[index], true)
    end
    return normalized
  end

  for index = 1, #node do
    normalized[index] = ast.normalize_node(node[index], true)
  end
  return normalized
end

local function serialize(node, buffer)
  if type(node) ~= "table" then
    buffer[#buffer + 1] = tostring(node)
    return
  end
  if not node.tag then
    -- Tagless arrays are ordered containers, not labeled subtrees.
    buffer[#buffer + 1] = "("
    for index, child in ipairs(node) do
      if index > 1 then
        buffer[#buffer + 1] = " "
      end
      serialize(child, buffer)
    end
    buffer[#buffer + 1] = ")"
    return
  end
  buffer[#buffer + 1] = "("
  buffer[#buffer + 1] = tostring(node.tag)
  for _, child in ipairs(node) do
    buffer[#buffer + 1] = " "
    serialize(child, buffer)
  end
  buffer[#buffer + 1] = ")"
end

function ast.serialize(node)
  local buffer = {}
  serialize(node, buffer)
  return table.concat(buffer)
end

function ast.build_fingerprints(node)
  local fingerprints = {}
  local count = 0
  local function collect(subtree)
    if type(subtree) ~= "table" then
      return
    end
    local key = ast.serialize(subtree)
    if not fingerprints[key] then
      fingerprints[key] = true
      count = count + 1
    end
    for _, child in ipairs(subtree) do
      collect(child)
    end
  end
  collect(node)
  return fingerprints, count
end

return ast
