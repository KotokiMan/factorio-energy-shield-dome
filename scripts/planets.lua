-- Per-surface rules. To enable a planet later, flip `enabled` and tune `cost_multiplier`.
local M = {}

local rules = {
  nauvis   = { enabled = true,  cost_multiplier = 1 },
  gleba    = { enabled = true,  cost_multiplier = 1 },
  fulgora  = { enabled = false, reason = { "esd-reason.fulgora" } },
  vulcanus = { enabled = false, reason = { "esd-reason.not-calibrated" } },
  aquilo   = { enabled = false, reason = { "esd-reason.not-calibrated" } },
}

local default_rule = { enabled = true, cost_multiplier = 1 }
local space_rule = { enabled = false, reason = { "esd-reason.space" } }

function M.get(surface)
  if surface.platform then
    return space_rule
  end
  local planet = surface.planet
  if planet then
    return rules[planet.name] or default_rule
  end
  return default_rule
end

return M
