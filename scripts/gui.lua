-- Generator window: status, buffer, radius slider, on/off.
local config = require("scripts.config")
local shield = require("scripts.shield")
local pool = require("scripts.pool")
local format = require("scripts.format")
local status = require("scripts.status")

local M = {}

local FRAME = "esd_frame"

function M.close(player)
  local data = storage.guis[player.index]
  if data and data.frame.valid then
    data.frame.destroy()
  end
  storage.guis[player.index] = nil
end

function M.open(player, sh)
  M.close(player)
  local frame = player.gui.screen.add({ type = "frame", name = FRAME, direction = "vertical" })

  local title = frame.add({ type = "flow", direction = "horizontal" })
  title.drag_target = frame
  title.add({ type = "label", caption = { "esd-gui.title" }, style = "frame_title", ignored_by_interaction = true })
  local filler = title.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  title.add({ type = "sprite-button", name = "esd_close", style = "frame_action_button", sprite = "utility/close" })

  local inner = frame.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  inner.style.minimal_width = 340
  local refs = {}
  refs.state = inner.add({ type = "label" })
  refs.state.style.font = "default-bold"
  refs.role = inner.add({ type = "label" })
  refs.reason = inner.add({ type = "label" })
  refs.reason.style.font_color = { r = 1, g = 0.4, b = 0.3 }
  refs.buffer_bar = inner.add({ type = "progressbar" })
  refs.buffer_bar.style.horizontally_stretchable = true
  refs.buffer = inner.add({ type = "label" })
  refs.upkeep = inner.add({ type = "label" })
  refs.radius = inner.add({ type = "label" })
  local stats_flow = inner.add({ type = "flow", direction = "vertical" })
  stats_flow.style.top_margin = 6
  refs.kills = stats_flow.add({ type = "label" })
  refs.dealt = stats_flow.add({ type = "label" })
  refs.absorbed = stats_flow.add({ type = "label" })

  local row = inner.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  row.style.top_margin = 8
  row.add({ type = "label", caption = { "esd-gui.target-radius" } })
  local primary = shield.primary_of(sh)
  local max_radius = shield.max_radius_for(primary)
  refs.slider = row.add({
    type = "slider", name = "esd_slider",
    minimum_value = config.min_radius, maximum_value = max_radius,
    value = math.min(primary.target, max_radius), value_step = 1,
  })
  refs.slider.style.horizontally_stretchable = true
  refs.target = row.add({ type = "label" })
  refs.target.style.minimal_width = 30

  refs.field_toggle = inner.add({
    type = "checkbox", name = "esd_field_toggle", caption = { "esd-gui.field-enabled" },
    tooltip = { "esd-gui.field-enabled-tooltip" }, state = primary.field_enabled ~= false,
  })
  refs.field_toggle.style.top_margin = 12
  local reserve_row = inner.add({ type = "flow", direction = "horizontal" })
  reserve_row.style.vertical_align = "center"
  reserve_row.style.top_margin = 4
  reserve_row.add({ type = "label", caption = { "esd-gui.field-reserve" }, tooltip = { "esd-gui.field-reserve-tooltip" } })
  refs.reserve_slider = reserve_row.add({
    type = "slider", name = "esd_reserve_slider", minimum_value = 0, maximum_value = config.max_field_reserve,
    value = primary.field_reserve or config.default_field_reserve, value_step = 5,
    tooltip = { "esd-gui.field-reserve-tooltip" },
  })
  refs.reserve_slider.style.horizontally_stretchable = true
  refs.reserve = reserve_row.add({ type = "label" })
  refs.reserve.style.minimal_width = 40

  refs.toggle = inner.add({ type = "button", name = "esd_toggle" })
  refs.toggle.style.top_margin = 8

  frame.auto_center = true
  player.opened = frame
  storage.guis[player.index] = { frame = frame, id = sh.id, refs = refs }
  M.refresh(player.index)
end

function M.refresh(player_index)
  local data = storage.guis[player_index]
  if not data then return end
  local sh = storage.shields[data.id]
  if not (data.frame.valid and sh and sh.entity.valid) then
    local player = game.get_player(player_index)
    if player then M.close(player) end
    return
  end
  local refs = data.refs
  local primary = shield.primary_of(sh)

  refs.state.caption = status.state_caption(primary)

  local count = pool.count(primary)
  if sh.role == "support" then
    refs.role.caption = { "esd-gui.role-support", tostring(count), tostring(shield.max_generators()) }
  elseif sh.role == "idle" then
    refs.role.caption = { "esd-gui.role-idle", tostring(shield.max_generators()) }
  else
    refs.role.caption = { "esd-gui.role-primary", tostring(count), tostring(shield.max_generators()) }
  end

  local reason = primary.reason
  if not reason and primary.blocked then
    reason = { "esd-reason.blocked" }
  end
  refs.reason.caption = reason or ""
  refs.reason.visible = reason ~= nil

  local energy, buffer = pool.energy(primary), pool.buffer(primary)
  refs.buffer_bar.value = buffer > 0 and energy / buffer or 0
  refs.buffer.caption = { "esd-gui.buffer", format.si(energy, "J"), format.si(buffer, "J") }
  local upkeep = shield.is_active(primary) and primary.upkeep_watts or 0
  refs.upkeep.caption = { "esd-gui.upkeep", format.si(upkeep, "W") }
  refs.radius.caption = { "esd-gui.radius", tostring(primary.radius), tostring(shield.effective_target(primary)) }

  local stats = pool.stats(primary)
  refs.kills.caption = { "esd-hover.kills", format.si(stats.kills) }
  refs.dealt.caption = { "esd-hover.dealt", format.si(stats.dealt) }
  refs.absorbed.caption = { "esd-hover.absorbed", format.si(stats.absorbed) }

  local max_radius = shield.max_radius_for(primary)
  if refs.slider.get_slider_maximum() ~= max_radius then
    refs.slider.set_slider_minimum_maximum(config.min_radius, max_radius)
  end
  refs.target.caption = tostring(math.min(primary.target, max_radius))
  local reserve = primary.field_reserve or config.default_field_reserve
  refs.reserve.caption = reserve .. "%"
  if refs.reserve_slider.slider_value ~= reserve then refs.reserve_slider.slider_value = reserve end
  local field_on = primary.field_enabled ~= false
  refs.field_toggle.state = field_on
  refs.reserve_slider.enabled = field_on
  refs.toggle.caption = primary.enabled and { "esd-gui.turn-off" } or { "esd-gui.turn-on" }
end

function M.refresh_all()
  for player_index in pairs(storage.guis) do
    M.refresh(player_index)
  end
end

local function shield_of(player_index)
  local data = storage.guis[player_index]
  return data and storage.shields[data.id]
end

function M.on_click(event)
  local name = event.element.name
  local player = game.get_player(event.player_index)
  if name == "esd_close" then
    M.close(player)
  elseif name == "esd_toggle" then
    local sh = shield_of(event.player_index)
    if sh then
      shield.set_enabled(sh, not shield.primary_of(sh).enabled)
      M.refresh(event.player_index)
    end
  end
end

function M.on_checked_state_changed(event)
  if event.element.name ~= "esd_field_toggle" then return end
  local sh = shield_of(event.player_index)
  if sh then
    shield.set_field_enabled(sh, event.element.state)
    M.refresh(event.player_index)
  end
end

function M.on_value_changed(event)
  local name = event.element.name
  if name ~= "esd_slider" and name ~= "esd_reserve_slider" then return end
  local sh = shield_of(event.player_index)
  if sh then
    if name == "esd_slider" then
      shield.set_target(sh, event.element.slider_value)
    else
      shield.set_field_reserve(sh, event.element.slider_value)
    end
    M.refresh(event.player_index)
  end
end

function M.on_closed(event)
  local element = event.element
  if element and element.valid and element.name == FRAME then
    M.close(game.get_player(event.player_index))
  end
end

return M
