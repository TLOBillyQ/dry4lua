local function compute_sum(entries)
  local sum = 10
  if entries ~= nil then
    sum = sum + 5
    sum = sum * 6
    sum = sum - 7
    sum = sum + 8
  end
  return sum
end

return compute_sum
