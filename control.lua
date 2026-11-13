local shared = require("shared")
local config = require("scripts.config")
local shield = require("scripts.shield")
local gui = require("scripts.gui")
local render = require("scripts.render")
local map = require("scripts.map")
local pool = require("scripts.pool")

script.on_init(shield.init)

script.on_configuration_changed(function()
  shield.init()
  shield.on_configuration_changed()
end)

-- Building --------------------------------------------------------------

local function on_built(event)
  local entity = event.entity
  if entity and entity.valid and entity.name == shared.generator then
    shield.add(entity, event.tags)
  end
end

local built_filter = { { filter = "name", name = shared.generator } }
for _, id in pairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(id, on_built, built_filter)
end

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.type == defines.target_type.entity and event.useful_id then
    shield.remove(event.useful_id)
  end
end)

-- Shield logic ----------------------------------------------------------

script.on_nth_tick(config.update_interval, function()
  shield.update_all()
  gui.refresh_all()
end)

script.on_nth_tick(config.stream_scan_ticks, shield.block_streams_all)

script.on_event(defines.events.on_entity_damaged, shield.on_damaged)

-- Ripples are animated only while there are any.
script.on_event(defines.events.on_tick, function(event)
  if storage.ripples and storage.ripples[1] then
    render.tick_ripples(event.tick)
  end
end)

local function on_research(event)
  local tech = event.research
  if tech.name:find(shared.radius_tech_prefix, 1, true) == 1 then
    shield.recompute_max_radius(tech.force)
  end
end
script.on_event(defines.events.on_research_finished, on_research)
script.on_event(defines.events.on_research_reversed, on_research)
-- Console / other mods changing technology levels: re-read the radius research.
script.on_event(defines.events.on_technology_effects_reset, function(event)
  shield.recompute_max_radius(event.force)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "esd-max-radius-cap" or event.setting == "esd-max-generators" then
    shield.retarget_all()
  elseif event.setting == "esd-dome-glow" then
    render.refresh_glow_visibility()
  end
end)

local function on_players_changed()
  render.refresh_glow_visibility()
  map.refresh_visibility()
end
script.on_event(defines.events.on_player_joined_game, on_players_changed)
script.on_event(defines.events.on_player_left_game, on_players_changed)

-- Map overlay toggle: shortcut button or Ctrl+Shift+D.
script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == shared.map_shortcut then
    map.toggle(game.get_player(event.player_index))
  end
end)
script.on_event(shared.map_input, function(event)
  map.toggle(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_entity_settings_pasted, function(event)
  local from, to = shield.get(event.source), shield.get(event.destination)
  if from and to then
    shield.copy_settings(from, to)
  end
end)

-- Remote interface (tests and other mods) --------------------------------

remote.add_interface("energy-shield-dome", {
  get_state = function(unit_number)
    local sh = storage.shields[unit_number]
    if not sh then return nil end
    local primary = shield.primary_of(sh)
    return {
      role = sh.role,
      primary = primary.id,
      supports = #primary.supports,
      state = primary.state,
      radius = primary.radius,
      target = shield.effective_target(primary),
      max_radius = shield.max_radius_for(primary),
      energy = pool.energy(primary),
      buffer = pool.buffer(primary),
      barrier = #primary.barrier,
      blocked = primary.blocked or false,
      paused = primary.paused or false,
      stats = pool.stats(primary),
    }
  end,
  set_target = function(unit_number, radius)
    local sh = storage.shields[unit_number]
    if sh then shield.set_target(sh, radius) end
  end,
  set_field_reserve = function(unit_number, percent)
    local sh = storage.shields[unit_number]
    if sh then shield.set_field_reserve(sh, percent) end
  end,
  set_field_enabled = function(unit_number, enabled)
    local sh = storage.shields[unit_number]
    if sh then shield.set_field_enabled(sh, enabled) end
  end,
  set_enabled = function(unit_number, enabled)
    local sh = storage.shields[unit_number]
    if sh then shield.set_enabled(sh, enabled) end
  end,
})

-- GUI -------------------------------------------------------------------

script.on_event(shared.open_input, function(event)
  local player = game.get_player(event.player_index)
  local entity = player.selected
  if not (entity and entity.valid and entity.name == shared.generator) then return end
  if not entity.force.is_friend(player.force) and entity.force ~= player.force then return end
  local sh = shield.get(entity)
  if sh then
    gui.open(player, sh)
  end
end)

script.on_event(defines.events.on_gui_click, gui.on_click)
script.on_event(defines.events.on_gui_value_changed, gui.on_value_changed)
script.on_event(defines.events.on_gui_checked_state_changed, gui.on_checked_state_changed)
script.on_event(defines.events.on_gui_closed, gui.on_closed)
