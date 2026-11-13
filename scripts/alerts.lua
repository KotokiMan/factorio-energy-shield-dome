-- Vanilla-style custom alerts: "dome under attack" and "dome collapsed".
-- Each player can turn them off in the per-player mod settings.
local shared = require("shared")
local config = require("scripts.config")

local M = {}

local ICON = { type = "item", name = shared.generator }

-- `target` is the entity the alert points at (map position of the alert).
local function notify(sh, message, target)
  local ent = sh.entity
  if not ent.valid then return end
  if not (target and target.valid) then target = ent end
  for _, player in pairs(ent.force.connected_players) do
    if settings.get_player_settings(player)["esd-alerts"].value then
      player.add_custom_alert(target, ICON, message, true)
    end
  end
end

-- Points at the spot being hit: the barrier segment or the damaged building.
function M.under_attack(sh, hit_entity)
  local tick = game.tick
  if tick < (sh.next_attack_alert or 0) then return end
  sh.next_attack_alert = tick + config.alert_cooldown_ticks
  notify(sh, { "esd-alert.under-attack" }, hit_entity)
end

-- Points at the dome centre (primary generator).
function M.collapsed(sh)
  notify(sh, { "esd-alert.collapsed" })
end

return M
