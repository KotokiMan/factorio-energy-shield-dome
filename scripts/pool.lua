-- Shared energy of a dome: the primary generator plus its supporting generators.
-- Also keeps the dome's combat statistics.
local M = {}

function M.stats(sh)
  local s = sh.stats
  if not s then
    s = { kills = 0, dealt = 0, absorbed = 0 }
    sh.stats = s
  end
  return s
end

function M.members(sh)
  local list = { sh.entity }
  for _, id in pairs(sh.supports) do
    local support = storage.shields[id]
    if support and support.entity.valid then
      list[#list + 1] = support.entity
    end
  end
  return list
end

function M.count(sh)
  return #M.members(sh)
end

function M.energy(sh)
  local total = 0
  for _, e in pairs(M.members(sh)) do
    total = total + e.energy
  end
  return total
end

function M.buffer(sh)
  local total = 0
  for _, e in pairs(M.members(sh)) do
    total = total + e.electric_buffer_size
  end
  return total
end

-- Takes `amount` from all members in proportion to what each holds.
-- Returns false (and empties the pool) if there was not enough.
function M.drain(sh, amount)
  if amount <= 0 then return true end
  local members = M.members(sh)
  local total = 0
  for _, e in pairs(members) do
    total = total + e.energy
  end
  if amount > total then
    for _, e in pairs(members) do
      e.energy = 0
    end
    return false
  end
  local keep = 1 - amount / total
  for _, e in pairs(members) do
    e.energy = e.energy * keep
  end
  return true
end

function M.empty(sh)
  for _, e in pairs(M.members(sh)) do
    e.energy = 0
  end
end

return M
