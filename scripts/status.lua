-- Entity status shown in the side info panel when the generator is hovered and in its
-- window: dome state + combat statistics (like turret kills / damage dealt).
local pool = require("scripts.pool")
local format = require("scripts.format")

local M = {}

local DIODE = {
  stable = defines.entity_status_diode.green,
  expanding = defines.entity_status_diode.yellow,
  charging = defines.entity_status_diode.yellow,
}

-- Localised state line; cooldown shows seconds left.
function M.state_caption(primary)
  local state = { "esd-state." .. primary.state }
  if primary.state == "expanding" and primary.paused then
    state = { "", state, " ", { "esd-state.paused" } }
  elseif primary.state == "cooldown" and primary.cooldown_until then
    local left = math.max(0, math.ceil((primary.cooldown_until - game.tick) / 60))
    state = { "", state, " ", { "esd-state.seconds", tostring(left) } }
  end
  return state
end

function M.update(sh, primary)
  local ent = sh.entity
  local s = pool.stats(primary)
  local state = sh.role == "idle" and "idle" or primary.state
  local key = state .. (primary.paused and "p" or "") .. s.kills .. ":" .. math.floor(s.dealt) .. ":" .. math.floor(s.absorbed)
    .. ((state == "cooldown" and primary.cooldown_until) and math.ceil((primary.cooldown_until - game.tick) / 60) or "")
  if sh.status_key == key then return end
  sh.status_key = key
  local first = sh.role == "idle" and { "esd-state.idle" } or M.state_caption(primary)
  ent.custom_status = {
    diode = DIODE[state] or defines.entity_status_diode.red,
    label = { "", first,
      "\n", { "esd-hover.kills", format.si(s.kills) },
      "\n", { "esd-hover.dealt", format.si(s.dealt) },
      "\n", { "esd-hover.absorbed", format.si(s.absorbed) } },
  }
end

return M
