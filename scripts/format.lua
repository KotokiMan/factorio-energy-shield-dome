local M = {}

local PREFIXES = { "", "k", "M", "G", "T", "P" }

-- 1234567 -> "1.2 M" + unit
function M.si(value, unit)
  local i = 1
  while value >= 1000 and i < #PREFIXES do
    value = value / 1000
    i = i + 1
  end
  local fmt = (i == 1) and "%.0f %s%s" or "%.1f %s%s"
  return string.format(fmt, value, PREFIXES[i], unit or "")
end

return M
