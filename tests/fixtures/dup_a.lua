local function calculate_total(records)
  local total = 0
  if records ~= nil then
    total = total + 1
    total = total * 2
    total = total - 3
    total = total + 4
  end
  return total
end

return calculate_total
