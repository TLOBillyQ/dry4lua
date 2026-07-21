local function render_report(title)
  local output = title
  if output == "" then
    output = "untitled"
  elseif output == "x" then
    output = "ex"
  else
    output = output .. "!"
  end
  return output
end

return render_report
