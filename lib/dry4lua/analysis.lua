local ast = require("dry4lua.ast")

local analysis = {}

local DEFAULT_OPTIONS = {
  threshold = 0.82,
  min_lines = 4,
  min_nodes = 20,
}

local function jaccard(fps_a, count_a, fps_b, count_b)
  local small, big = fps_a, fps_b
  if count_a > count_b then
    small, big = fps_b, fps_a
  end
  local intersection = 0
  for key in pairs(small) do
    if big[key] then
      intersection = intersection + 1
    end
  end
  local union = count_a + count_b - intersection
  if union == 0 then
    return 0
  end
  return intersection / union
end

local function collect_files(paths)
  local files = {}
  local handle = io.popen("find " .. table.concat(paths, " ") .. " -name '*.lua' -type f 2>/dev/null")
  if handle then
    for line in handle:lines() do
      files[#files + 1] = line
    end
    handle:close()
  end
  table.sort(files)
  return files
end

local function scan_file(path, entries, options)
  local chunk, err = ast.parse_file(path)
  if not chunk then
    return
  end
  local functions = ast.extract_functions(chunk)
  for _, entry in ipairs(functions) do
    local line_count = entry.end_line - entry.start_line + 1
    if line_count >= options.min_lines then
      local node_count = ast.count_nodes(entry.node)
      if node_count >= options.min_nodes then
        local normalized = ast.normalize_node(entry.node)
        local fingerprints, fp_count = ast.build_fingerprints(normalized)
        entries[#entries + 1] = {
          file = path,
          name = entry.name,
          start_line = entry.start_line,
          end_line = entry.end_line,
          fingerprints = fingerprints,
          fp_count = fp_count,
        }
      end
    end
  end
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
    if a.fp_count ~= b.fp_count then
      return a.fp_count < b.fp_count
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.start_line < b.start_line
  end)

  local candidates = {}
  for i = 1, #entries do
    local a = entries[i]
    for j = i + 1, #entries do
      local b = entries[j]
      if a.fp_count / b.fp_count < threshold then
        break
      end
      local score = jaccard(a.fingerprints, a.fp_count, b.fingerprints, b.fp_count)
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
