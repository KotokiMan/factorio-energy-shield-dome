-- Map overlay (chart render mode), toggled per player with a shortcut button:
-- generator markers, dome edge, the electric field ring (like turret ranges) and hit flashes.
local shared = require("shared")

local M = {}

local PI = math.pi
local EDGE = { r = 0.35, g = 0.6, b = 0.8, a = 0.8 }
local FIELD = { r = 0.35, g = 0.08, b = 0.05, a = 0.35 }  -- reddish, like turret ranges
local HIT = { r = 0.9, g = 0.9, b = 1, a = 0.9 }
local MAX_HITS = 4
local HIT_WINDOW = 30

local function viewers()
  local list = {}
  for index, on in pairs(storage.map_players) do
    local player = on and game.get_player(index)
    if player and player.valid and player.connected then
      list[#list + 1] = index
    end
  end
  return list
end

-- An empty `players` list would mean "everyone", so hide the object instead.
local function apply(obj, list)
  if not (obj and obj.valid) then return end
  if #list == 0 then
    obj.visible = false
  else
    obj.players = list
    obj.visible = true
  end
end

local function objects_of(sh)
  local list = {}
  if sh.chart then
    for _, obj in pairs(sh.chart) do list[#list + 1] = obj end
  end
  if sh.chart_icon then list[#list + 1] = sh.chart_icon end
  return list
end

function M.ensure_icon(sh)
  if sh.chart_icon and sh.chart_icon.valid then return end
  local ent = sh.entity
  sh.chart_icon = rendering.draw_sprite({
    sprite = "item/" .. shared.generator, target = ent, surface = ent.surface,
    render_mode = "chart", x_scale = 1.2, y_scale = 1.2, visible = false,
  })
  apply(sh.chart_icon, viewers())
end

function M.update_dome(sh, width)
  local ent, r = sh.entity, sh.radius
  local chart = sh.chart
  if not (chart and chart.edge.valid and chart.field.valid) then
    M.destroy_dome(sh)
    chart = {
      field = rendering.draw_arc({
        color = FIELD, min_radius = r, max_radius = r + width, start_angle = 0, angle = 2 * PI,
        target = ent, surface = ent.surface, render_mode = "chart", visible = false,
      }),
      edge = rendering.draw_circle({
        color = EDGE, radius = r, width = 3, filled = false,
        target = ent, surface = ent.surface, render_mode = "chart", visible = false,
      }),
    }
    sh.chart = chart
    local list = viewers()
    apply(chart.field, list)
    apply(chart.edge, list)
    return
  end
  chart.edge.radius = r
  chart.field.min_radius = r
  chart.field.max_radius = r + width
end

function M.destroy_dome(sh)
  if sh.chart then
    for _, obj in pairs(sh.chart) do
      if obj.valid then obj.destroy() end
    end
  end
  sh.chart = nil
end

function M.destroy_all(sh)
  M.destroy_dome(sh)
  if sh.chart_icon and sh.chart_icon.valid then sh.chart_icon.destroy() end
  sh.chart_icon = nil
end

function M.hit(sh, position)
  local list = viewers()
  if #list == 0 then return end
  local tick = game.tick
  if tick >= (sh.map_hit_window or 0) then
    sh.map_hit_window = tick + HIT_WINDOW
    sh.map_hits = 0
  end
  if sh.map_hits >= MAX_HITS then return end
  sh.map_hits = sh.map_hits + 1
  rendering.draw_circle({
    color = HIT, radius = 2.5, filled = true, target = position, surface = sh.entity.surface,
    render_mode = "chart", time_to_live = 45, players = list,
  })
end

function M.refresh_visibility()
  local list = viewers()
  for _, sh in pairs(storage.shields) do
    for _, obj in pairs(objects_of(sh)) do
      apply(obj, list)
    end
  end
end

function M.toggle(player)
  local on = not storage.map_players[player.index]
  storage.map_players[player.index] = on or nil
  player.set_shortcut_toggled(shared.map_shortcut, on)
  M.refresh_visibility()
end

return M
