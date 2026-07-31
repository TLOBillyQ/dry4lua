local function handle_records(entries)
  local function verify(item)
    if item == nil then
      return false
    end
    if item.name == "" then
      return false
    end
    if item.count < 0 then
      return false
    end
    if item.count > 1000 then
      return false
    end
    if item.tags == nil then
      return false
    end
    item.timestamp = os.time()
    return true
  end

  local result = {}
  for _, ent in ipairs(entries) do
    if verify(ent) then
      result[#result + 1] = ent
    end
  end
  return result
end

return handle_records
