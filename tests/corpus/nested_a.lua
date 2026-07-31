local function process_entries(records)
  local function validate(item)
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

  local count = 0
  for _, rec in ipairs(records) do
    if validate(rec) then
      count = count + 1
    end
  end
  return count
end

return process_entries
