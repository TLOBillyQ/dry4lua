local lexer = require("dry4lua.lexer")
local scope_mod = require("dry4lua.scope")

local analysis = {}

local DEFAULT_OPTIONS = {
  threshold = 0.82,
  min_lines = 4,
  min_nodes = 20,
}

local function normalize_tokens(tokens, scope)
  local normalized = {}
  for _, tok in ipairs(tokens) do
    if tok.start_pos >= scope.start_pos and tok.end_pos <= scope.end_pos then
      local value
      if tok.type == "keyword" or tok.type == "symbol" then
        value = tok.value
      elseif tok.type == "identifier" then
        value = "_ID"
      elseif tok.type == "number" then
        value = "_NUM"
      elseif tok.type == "string" then
        value = "_STR"
      end
      if value then
        normalized[#normalized + 1] = value
      end
    end
  end
  return normalized
end

local function build_fingerprints(normalized)
  local fps = {}
  local count = 0
  local max_window = math.min(7, #normalized)
  for window = 3, max_window do
    for i = 1, #normalized - window + 1 do
      local key = table.concat(normalized, " ", i, i + window - 1)
      if not fps[key] then
        fps[key] = true
        count = count + 1
      end
    end
  end
  return fps, count
end

local function jaccard(fps_a, fps_b)
  local intersection = 0
  local union = 0
  for k in pairs(fps_a) do
    union = union + 1
    if fps_b[k] then
      intersection = intersection + 1
    end
  end
  for k in pairs(fps_b) do
    if not fps_a[k] then
      union = union + 1
    end
  end
  if union == 0 then
    return 0
  end
  return intersection / union
end

local function scan_file(path, entries, options)
  local file = io.open(path, "r")
  if not file then
    return
  end
  local source = file:read("*a")
  file:close()
  local tokens = lexer.tokenize(source)
  local scopes = scope_mod.extract(tokens)
  for _, scope in ipairs(scopes) do
    local line_count = scope.end_line - scope.start_line + 1
    if line_count >= options.min_lines then
      local normalized = normalize_tokens(tokens, scope)
      if #normalized >= options.min_nodes then
        local fps, fp_count = build_fingerprints(normalized)
        entries[#entries + 1] = {
          file = path,
          name = scope.name,
          start_line = scope.start_line,
          end_line = scope.end_line,
          fingerprints = fps,
          fp_count = fp_count,
        }
      end
    end
  end
end

local function collect_files(paths)
  local files = {}
  for _, path in ipairs(paths) do
    local handle = io.popen("find " .. path .. " -name '*.lua' -type f 2>/dev/null")
    if handle then
      for line in handle:lines() do
        files[#files + 1] = line
      end
      handle:close()
    end
  end
  table.sort(files)
  return files
end

function analysis.find_duplicates(options)
  options = options or {}
  local threshold = options.threshold or DEFAULT_OPTIONS.threshold
  local min_lines = options.min_lines or DEFAULT_OPTIONS.min_lines
  local min_nodes = options.min_nodes or DEFAULT_OPTIONS.min_nodes
  local paths = options.paths or { "src" }

  local scan_opts = { min_lines = min_lines, min_nodes = min_nodes }
  local files = collect_files(paths)
  local entries = {}
  for _, path in ipairs(files) do
    scan_file(path, entries, scan_opts)
  end

  table.sort(entries, function(a, b)
    return a.fp_count < b.fp_count
  end)

  local candidates = {}
  for i = 1, #entries do
    local a = entries[i]
    for j = i + 1, #entries do
      local b = entries[j]
      if a.fp_count / b.fp_count < threshold then
        break
      end
      local score = jaccard(a.fingerprints, b.fingerprints)
      if score >= threshold then
        candidates[#candidates + 1] = {
          score = score,
          left = { file = a.file, name = a.name, start_line = a.start_line, end_line = a.end_line },
          right = { file = b.file, name = b.name, start_line = b.start_line, end_line = b.end_line },
        }
      end
    end
  end

  table.sort(candidates, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.left.file ~= b.left.file then
      return a.left.file < b.left.file
    end
    return a.left.start_line < b.left.start_line
  end)

  return candidates
end

return analysis
