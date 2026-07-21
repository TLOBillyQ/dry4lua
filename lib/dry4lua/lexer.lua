local lexer = {}

local byte = string.byte
local sub = string.sub
local match = string.match

-- Find patterns for skipping to the next quote-body delimiter or escape.
local QUOTE_SCAN = { [39] = "[\\']", [34] = '[\\"]' }

local keywords = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

-- Byte classes as bit flags (C locale, matching the original patterns).
local C_NAME_START = 2  -- [%a_]
local C_NAME_CHAR = 4   -- [%w_]
local C_DIGIT = 8       -- %d
local C_HEX = 16        -- [%da-fA-F]
local C_BIN = 32        -- [01]
local C_BLANK = 64      -- whitespace except "\n"

local classes = {}
for b = 0, 255 do
  local class = 0
  if b == 32 or b == 9 or (b >= 11 and b <= 13) then
    class = class + C_BLANK
  end
  if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
    class = class + C_NAME_START + C_NAME_CHAR
  end
  if b >= 48 and b <= 57 then
    class = class + C_NAME_CHAR + C_DIGIT + C_HEX
  end
  if (b >= 65 and b <= 70) or (b >= 97 and b <= 102) then
    class = class + C_HEX
  end
  if b == 48 or b == 49 then
    class = class + C_BIN
  end
  classes[b] = class
end

local function count_newlines(text)
  local count = 0
  local pos = text:find("\n", 1, true)
  while pos do
    count = count + 1
    pos = text:find("\n", pos + 1, true)
  end
  return count
end

local function long_bracket_equals(source, index)
  if byte(source, index) ~= 91 then -- "["
    return nil
  end
  local cursor = index + 1
  while byte(source, cursor) == 61 do -- "="
    cursor = cursor + 1
  end
  if byte(source, cursor) ~= 91 then -- "["
    return nil
  end
  return cursor - index - 1
end

local function close_long_bracket(source, index, equals_count)
  local closer = "]" .. string.rep("=", equals_count) .. "]"
  return source:find(closer, index, true)
end

-- Consume a run of characters in the given class mask (underscores always
-- allowed), returning the cursor position just past the run.
local function consume_run(source, cursor, length, mask)
  while cursor <= length do
    local b = byte(source, cursor)
    if b ~= 95 and classes[b] & mask == 0 then -- "_"
      break
    end
    cursor = cursor + 1
  end
  return cursor
end

-- Consume an exponent suffix ("p"/"P"/"e"/"E", optional sign, digits).
local function consume_exponent(source, cursor, length, lower, upper)
  local b = byte(source, cursor)
  if b ~= lower and b ~= upper then
    return cursor
  end
  cursor = cursor + 1
  b = byte(source, cursor)
  if b == 43 or b == 45 then -- "+" / "-"
    cursor = cursor + 1
  end
  return consume_run(source, cursor, length, C_DIGIT)
end

local function scan_number(source, index, length)
  local prefix = byte(source, index + 1)
  local leading_zero = byte(source, index) == 48 -- "0"
  if leading_zero and (prefix == 120 or prefix == 88) then -- "x" / "X"
    local cursor = consume_run(source, index + 2, length, C_HEX)
    if byte(source, cursor) == 46 then -- "."
      cursor = consume_run(source, cursor + 1, length, C_HEX)
    end
    return consume_exponent(source, cursor, length, 112, 80) - 1 -- "p" / "P"
  end
  if leading_zero and (prefix == 98 or prefix == 66) then -- "b" / "B"
    return consume_run(source, index + 2, length, C_BIN) - 1
  end
  local cursor = consume_run(source, index, length, C_DIGIT)
  if byte(source, cursor) == 46 and byte(source, cursor + 1) ~= 46 then
    cursor = consume_run(source, cursor + 1, length, C_DIGIT)
  end
  return consume_exponent(source, cursor, length, 101, 69) - 1 -- "e" / "E"
end

function lexer.tokenize(source)
  source = tostring(source or "")
  if source:find("\r", 1, true) then
    source = source:gsub("\r\n", "\n")
  end
  -- Local copies beat repeated upvalue lookups in the hot loop.
  local byte = byte
  local sub = sub
  local match = match
  local classes = classes
  local keywords = keywords
  local tokens = {}
  local count = 0
  local index = 1
  local line = 1
  local length = #source
  while index <= length do
    local b = byte(source, index)
    if b == 10 then -- "\n"
      line = line + 1
      index = index + 1
    elseif classes[b] & C_BLANK ~= 0 then
      -- [^%S\n] = whitespace except newline; match consumes the whole run.
      index = index + #match(source, "^[^%S\n]*", index)
    elseif b == 45 and byte(source, index + 1) == 45 then -- "--"
      local equals_count = long_bracket_equals(source, index + 2)
      if equals_count then
        local start_index = index + 2
        local close_index = close_long_bracket(source, start_index, equals_count)
        if not close_index then
          local chunk = sub(source, index)
          line = line + count_newlines(chunk)
          break
        end
        local chunk_end = close_index + equals_count + 2
        local chunk = sub(source, index, chunk_end)
        line = line + count_newlines(chunk)
        index = chunk_end + 1
      else
        local newline = source:find("\n", index, true)
        if not newline then
          break
        end
        line = line + 1
        index = newline + 1
      end
    elseif b == 39 or b == 34 then -- "'" / '"'
      -- Jump between delimiter/escape hits in C instead of per-char in Lua.
      local pattern = QUOTE_SCAN[b]
      local cursor = index + 1
      while true do
        local pos = source:find(pattern, cursor)
        if not pos then
          cursor = length + 1
          break
        end
        if byte(source, pos) == 92 then -- "\"
          cursor = pos + 2
        else
          cursor = pos
          break
        end
      end
      if cursor > length then
        cursor = length
      end
      local text = sub(source, index, cursor)
      count = count + 1
      tokens[count] = {
        type = "string", value = text,
        start_pos = index, end_pos = cursor, line = line,
      }
      line = line + count_newlines(text)
      index = cursor + 1
    elseif b == 91 then -- "["
      local equals_count = long_bracket_equals(source, index)
      if equals_count then
        local close_index = close_long_bracket(source, index + 1, equals_count)
        local cursor = close_index and (close_index + equals_count + 2) or length
        local text = sub(source, index, cursor)
        count = count + 1
        tokens[count] = {
          type = "string", value = text,
          start_pos = index, end_pos = cursor, line = line,
        }
        line = line + count_newlines(text)
        index = cursor + 1
      else
        count = count + 1
        tokens[count] = {
          type = "symbol", value = "[",
          start_pos = index, end_pos = index, line = line,
        }
        index = index + 1
      end
    elseif classes[b] & C_NAME_START ~= 0 then
      local text = match(source, "^[%w_]+", index)
      local cursor = index + #text - 1
      count = count + 1
      tokens[count] = {
        type = keywords[text] and "keyword" or "identifier", value = text,
        start_pos = index, end_pos = cursor, line = line,
      }
      index = cursor + 1
    elseif classes[b] & C_DIGIT ~= 0 then
      local cursor = scan_number(source, index, length)
      count = count + 1
      tokens[count] = {
        type = "number", value = sub(source, index, cursor),
        start_pos = index, end_pos = cursor, line = line,
      }
      index = cursor + 1
    else
      local nb = byte(source, index + 1)
      local value
      if b == 46 then -- "."
        if nb == 46 then
          value = byte(source, index + 2) == 46 and "..." or ".."
        else
          value = "."
        end
      elseif nb == 61 and (b == 61 or b == 126 or b == 60 or b == 62) then
        value = sub(source, index, index + 1) -- "==" "~=" "<=" ">="
      else
        value = sub(source, index, index)
      end
      count = count + 1
      tokens[count] = {
        type = "symbol", value = value,
        start_pos = index, end_pos = index + #value - 1, line = line,
      }
      index = index + #value
    end
  end
  return tokens
end

return lexer
