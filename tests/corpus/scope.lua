local scope = {}

local block_starters = { ["if"] = true, ["for"] = true, ["while"] = true }

local function function_name(tokens, index)
  local token = tokens[index + 1]
  local parts = {}
  if token and token.value == "(" then
    return "anonymous@" .. tokens[index].line
  end
  while token do
    if token.value == "(" then
      break
    end
    if token.type == "identifier" or token.value == "." or token.value == ":" then
      parts[#parts + 1] = token.value
    else
      break
    end
    token = tokens[index + #parts + 1]
  end
  if #parts == 0 then
    return "anonymous@" .. tokens[index].line
  end
  return table.concat(parts)
end

local function should_push_do(tokens, index)
  local prev = tokens[index - 1]
  if not prev then
    return true
  end
  return not block_starters[prev.value]
end

function scope.extract(tokens)
  local scopes = {}
  local stack = {}
  for index, token in ipairs(tokens) do
    if token.type == "keyword" then
      if token.value == "function" then
        stack[#stack + 1] = {
          kind = "function",
          name = function_name(tokens, index),
          start_line = token.line,
          start_pos = token.start_pos,
        }
      elseif block_starters[token.value] then
        stack[#stack + 1] = { kind = token.value }
      elseif token.value == "do" then
        if should_push_do(tokens, index) then
          stack[#stack + 1] = { kind = "do" }
        end
      elseif token.value == "repeat" then
        stack[#stack + 1] = { kind = "repeat" }
      elseif token.value == "until" then
        for position = #stack, 1, -1 do
          if stack[position].kind == "repeat" then
            table.remove(stack, position)
            break
          end
        end
      elseif token.value == "end" then
        if #stack == 0 then
          -- skip
        else
          local block = table.remove(stack)
          if block.kind == "function" then
            scopes[#scopes + 1] = {
              name = block.name,
              start_line = block.start_line,
              end_line = token.line,
              start_pos = block.start_pos,
              end_pos = token.end_pos,
            }
          end
        end
      end
    end
  end
  return scopes
end

return scope
