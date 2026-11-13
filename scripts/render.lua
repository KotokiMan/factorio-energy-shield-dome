-- In-world visuals: the dome (vector silhouette + soft edge glow), hit ripples along the
-- dome edge, the collapse flash and the generator model (spinning torus + charge glow).
local config = require("scripts.config")

local M = {}

local PI = math.pi
local cos, sin, sqrt, min, max, atan2 = math.cos, math.sin, math.sqrt, math.min, math.max, math.atan2

local function tint(alpha)
  return { r = alpha, g = alpha, b = alpha, a = alpha }
end

-- Premultiplied pale cold blue at the given alpha.
local function edge_color(alpha)
  return { r = 0.62 * alpha, g = 0.85 * alpha, b = 1.0 * alpha, a = alpha }
end

---------------------------------------------------------------------------
-- Dome
--
-- In Factorio's view a hemisphere of radius r shows its south half as the ground
-- circle and its north half as a half-ellipse reaching K*r up the screen
-- (heights are drawn at ~0.71, so K = sqrt(1 + 0.5)).
---------------------------------------------------------------------------

local K = sqrt(1.5)
local ELLIPSE_SEGMENTS = 48
local ARC_HALF_WIDTH = 0.05           -- tiles
local GLOW_TILES_PER_SCALE = 16       -- dome-glow.png: 1024 px wide = 2r at scale r/16
local GLOW_OFFSET = (1 - K) / 2       -- x r: sprite centre vs dome centre

local BRIGHTNESS = { expanding = 1.0, stable = 0.6 }

local function ellipse_point(c, r, i)
  local phi = PI * i / ELLIPSE_SEGMENTS
  return { x = c.x + r * cos(phi), y = c.y - K * r * sin(phi) }
end

-- Players who want the soft glow (per-player setting). nil = everyone.
local function glow_viewers()
  local list, all = {}, true
  for _, player in pairs(game.connected_players) do
    if settings.get_player_settings(player)["esd-dome-glow"].value then
      list[#list + 1] = player.index
    else
      all = false
    end
  end
  if all then return nil end
  return list
end

local function apply_glow_visibility(obj)
  local list = glow_viewers()
  if list == nil then
    obj.players = {}   -- empty = everyone
    obj.visible = true
  elseif #list == 0 then
    obj.visible = false
  else
    obj.players = list
    obj.visible = true
  end
end

-- Other domes on the same surface that overlap this one. Their silhouettes hide the
-- parts of our outline that fall inside them, so touching domes read as one merged bubble.
local function neighbours(sh)
  local list, c, r = {}, sh.position, sh.radius
  for _, other in pairs(storage.shields) do
    if other ~= sh and other.role == "primary" and other.radius > 0 and other.surface_index == sh.surface_index then
      local o = other.position
      local d = sqrt((o.x - c.x) ^ 2 + (o.y - c.y) ^ 2)
      if d < r + other.radius then
        list[#list + 1] = { id = other.id, c = o, r = other.radius }
      end
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

local function signature(r, others)
  local parts = { tostring(r) }
  for _, o in pairs(others) do
    parts[#parts + 1] = o.id .. "@" .. o.r
  end
  return table.concat(parts, ",")
end

-- Screen silhouette of a dome: ground circle in the south, half-ellipse in the north.
local function in_silhouette(p, o)
  local dx, dy = p.x - o.c.x, p.y - o.c.y
  local r = o.r * 0.995
  if dy >= 0 then
    return dx * dx + dy * dy < r * r
  end
  return (dx * dx) / (r * r) + (dy * dy) / (K * K * r * r) < 1
end

local function on_ground_inside(p, o)
  local dx, dy = p.x - o.c.x, p.y - o.c.y
  local r = o.r * 0.995
  return dx * dx + dy * dy < r * r
end

local function hidden(p, others, test)
  for _, o in pairs(others) do
    if test(p, o) then return true end
  end
  return false
end

-- Visible angle runs of the ground circle between a0 and a1.
local function arc_runs(c, r, a0, a1, others, test)
  local runs = {}
  if #others == 0 then
    runs[1] = { a0, a1 }
    return runs
  end
  local n = max(24, math.ceil(r * (a1 - a0) / 1.5))
  local step = (a1 - a0) / n
  local from
  for i = 0, n do
    local a = a0 + step * (i + 0.5)
    local visible = i < n and not hidden({ x = c.x + r * cos(a), y = c.y + r * sin(a) }, others, test)
    if visible and not from then
      from = a0 + step * i
    elseif not visible and from then
      runs[#runs + 1] = { from, a0 + step * i }
      from = nil
    end
  end
  return runs
end

local function destroy_edges(dome)
  for _, item in pairs(dome.edges or {}) do
    if item.obj.valid then item.obj.destroy() end
  end
  dome.edges = {}
end

local EDGE_ALPHA = { front = 0.85, back = 0.3, line = 0.75, halo_arc = 0.16, halo_line = 0.14 }
local HALO_WIDTH = 0.7    -- tiles inside the edge
local HALO_LINE_PX = 14

local function build_edges(sh, others, b)
  local dome, ent, c, r = sh.dome, sh.entity, sh.position, sh.radius
  local surface = ent.surface
  destroy_edges(dome)
  local edges = dome.edges
  -- Ground contact line: front (south) half bright, back half faint behind the dome.
  -- Merged domes cannot use the glow sprite (it would show inside the neighbour), so a
  -- soft halo follows the visible outline instead.
  local merged = #others > 0
  for _, run in pairs(arc_runs(c, r, 0, PI, others, in_silhouette)) do
    edges[#edges + 1] = { kind = "front", obj = rendering.draw_arc({
      color = edge_color(EDGE_ALPHA.front * b), min_radius = r - ARC_HALF_WIDTH, max_radius = r + ARC_HALF_WIDTH,
      start_angle = run[1], angle = run[2] - run[1], target = ent, surface = surface,
    }) }
    if merged then
      local halo = rendering.draw_arc({
        color = edge_color(EDGE_ALPHA.halo_arc * b), min_radius = r - HALO_WIDTH, max_radius = r,
        start_angle = run[1], angle = run[2] - run[1], target = ent, surface = surface,
      })
      apply_glow_visibility(halo)
      edges[#edges + 1] = { kind = "halo_arc", obj = halo }
    end
  end
  for _, run in pairs(arc_runs(c, r, PI, 2 * PI, others, on_ground_inside)) do
    edges[#edges + 1] = { kind = "back", obj = rendering.draw_arc({
      color = edge_color(EDGE_ALPHA.back * b), min_radius = r - ARC_HALF_WIDTH, max_radius = r + ARC_HALF_WIDTH,
      start_angle = run[1], angle = run[2] - run[1], target = ent, surface = surface, draw_on_ground = true,
    }) }
  end
  -- Silhouette of the north half.
  for i = 1, ELLIPSE_SEGMENTS do
    local mid = ellipse_point(c, r, i - 0.5)
    if not hidden(mid, others, in_silhouette) then
      edges[#edges + 1] = { kind = "line", obj = rendering.draw_line({
        color = edge_color(EDGE_ALPHA.line * b), width = 1.5,
        from = ellipse_point(c, r, i - 1), to = ellipse_point(c, r, i), surface = surface,
      }) }
      if merged then
        local halo = rendering.draw_line({
          color = edge_color(EDGE_ALPHA.halo_line * b), width = HALO_LINE_PX,
          from = ellipse_point(c, r, i - 1), to = ellipse_point(c, r, i), surface = surface,
        })
        apply_glow_visibility(halo)
        edges[#edges + 1] = { kind = "halo_line", obj = halo }
      end
    end
  end
end

local function dome_valid(dome)
  if not (dome and dome.edges and dome.glow and dome.glow.valid) then return false end
  for _, item in pairs(dome.edges) do
    if not item.obj.valid then return false end
  end
  return true
end

function M.update_dome(sh)
  if not dome_valid(sh.dome) then
    M.destroy_dome(sh)
    local dome = { edges = {} }
    dome.glow = rendering.draw_sprite({
      sprite = "esd-dome-glow", target = { entity = sh.entity, offset = { 0, 0 } },
      surface = sh.entity.surface, render_layer = "light-effect", tint = tint(1),
    })
    apply_glow_visibility(dome.glow)
    sh.dome = dome
  end
  local dome, r = sh.dome, sh.radius
  local b = BRIGHTNESS[sh.state] or BRIGHTNESS.stable
  if dome.r ~= r then
    local scale = r / GLOW_TILES_PER_SCALE
    dome.glow.x_scale, dome.glow.y_scale = scale, scale
    dome.glow.target = { entity = sh.entity, offset = { 0, GLOW_OFFSET * r } }
    dome.r = r
  end
  local others = neighbours(sh)
  local sig = signature(r, others)
  if dome.sig ~= sig then
    build_edges(sh, others, b)
    dome.merged = #others > 0
    if dome.merged then
      dome.glow.visible = false
    else
      apply_glow_visibility(dome.glow)
    end
    dome.sig = sig
    dome.b = nil   -- recolour the glow below as well
  end
  if dome.b ~= b then
    dome.glow.color = tint(b)
    for _, item in pairs(dome.edges) do
      item.obj.color = edge_color(EDGE_ALPHA[item.kind] * b)
    end
    dome.b = b
  end
end

function M.destroy_dome(sh)
  local dome = sh.dome
  if dome then
    if dome.glow and dome.glow.valid then dome.glow.destroy() end
    destroy_edges(dome)
    -- Saves from before merged outlines.
    for _, key in pairs({ "front", "back" }) do
      if dome[key] and dome[key].valid then dome[key].destroy() end
    end
    for _, line in pairs(dome.lines or {}) do
      if line.valid then line.destroy() end
    end
  end
  sh.dome = nil
end

function M.refresh_glow_visibility()
  for _, sh in pairs(storage.shields) do
    local dome = sh.dome
    if dome and dome.glow and dome.glow.valid then
      if not dome.merged then apply_glow_visibility(dome.glow) end
      for _, item in pairs(dome.edges or {}) do
        if item.kind == "halo_arc" or item.kind == "halo_line" then apply_glow_visibility(item.obj) end
      end
    end
  end
end

function M.collapse(sh)
  if sh.radius <= 0 then return end
  local ent = sh.entity
  rendering.draw_circle({
    color = edge_color(1), radius = sh.radius, width = 4, filled = false,
    target = ent.position, surface = ent.surface, time_to_live = 20,
  })
  rendering.draw_circle({
    color = edge_color(0.5), radius = sh.radius * 0.97, width = 10, filled = false,
    target = ent.position, surface = ent.surface, time_to_live = 12,
  })
end

---------------------------------------------------------------------------
-- Ripples: a bright arc that runs along the dome edge from the hit point and fades.
-- Animated in on_tick, only while ripples exist; capped per dome.
---------------------------------------------------------------------------

local RIPPLE_SPREAD = 7          -- tiles to each side at the end of its life
local RIPPLE_STEP = 2            -- ticks between updates

local RIPPLE_LINE_SEGMENTS = 8

-- Bright white-blue core + wide soft halo.
local function ripple_core(alpha)
  return { r = 0.85 * alpha, g = 0.95 * alpha, b = 1.0 * alpha, a = alpha }
end
local RIPPLE_LAYERS = {
  { color = ripple_core, alpha = 1.0, width = 4, thick = 0.22 },
  { color = edge_color, alpha = 0.6, width = 16, thick = 0.8 },
}

-- South half: the dome edge is the ground circle -> arcs.
-- North half: the visible edge is the half-ellipse -> short polylines along it.
function M.ripple(sh, position)
  if (sh.ripples_active or 0) >= config.max_ripples or sh.radius <= 0 then return end
  local ent, c, r = sh.entity, sh.position, sh.radius
  local theta = atan2(position.y - c.y, position.x - c.x)
  local rp = { born = game.tick, theta = theta, id = sh.id, r = r, c = { x = c.x, y = c.y }, layers = {} }
  local north = sin(theta) < 0
  if north then
    rp.phi = -theta  -- same x on the ellipse: cos(phi) = cos(theta), phi in (0, pi)
  end
  for li, layer in pairs(RIPPLE_LAYERS) do
    local objs = {}
    if north then
      for i = 1, RIPPLE_LINE_SEGMENTS do
        objs[i] = rendering.draw_line({
          color = layer.color(layer.alpha), width = layer.width, from = position, to = position, surface = ent.surface,
        })
      end
    else
      local half = 0.6 / r
      objs[1] = rendering.draw_arc({
        color = layer.color(layer.alpha), min_radius = r - layer.thick, max_radius = r + layer.thick,
        start_angle = theta - half, angle = 2 * half, target = ent, surface = ent.surface,
      })
    end
    rp.layers[li] = objs
  end
  sh.ripples_active = (sh.ripples_active or 0) + 1
  storage.ripples[#storage.ripples + 1] = rp
end

local function each_object(rp, fn)
  for _, objs in pairs(rp.layers) do
    for _, obj in pairs(objs) do fn(obj) end
  end
end

local function ripple_valid(rp)
  local ok = true
  each_object(rp, function(obj) if not obj.valid then ok = false end end)
  return ok
end

function M.tick_ripples(tick)
  if tick % RIPPLE_STEP ~= 0 then return end
  local list = storage.ripples
  local i = 1
  while i <= #list do
    local rp = list[i]
    local t = (tick - rp.born) / config.ripple_ticks
    if t >= 1 or not rp.layers or not ripple_valid(rp) then
      if rp.layers then
        each_object(rp, function(obj) if obj.valid then obj.destroy() end end)
      end
      local sh = storage.shields[rp.id]
      if sh then sh.ripples_active = max(0, (sh.ripples_active or 1) - 1) end
      list[i] = list[#list]
      list[#list] = nil
    else
      local half = (0.6 + RIPPLE_SPREAD * t) / rp.r
      local fade = (1 - t) ^ 1.5
      local c, r = rp.c, rp.r
      for li, layer in pairs(RIPPLE_LAYERS) do
        local objs = rp.layers[li]
        local color = layer.color(layer.alpha * fade)
        if rp.phi then
          local a0 = max(0, rp.phi - half)
          local a1 = min(PI, rp.phi + half)
          local n = #objs
          local width = layer.width * (1 - 0.7 * t)
          for k = 1, n do
            local line = objs[k]
            local f0, f1 = a0 + (a1 - a0) * (k - 1) / n, a0 + (a1 - a0) * k / n
            line.from = { x = c.x + r * cos(f0), y = c.y - K * r * sin(f0) }
            line.to = { x = c.x + r * cos(f1), y = c.y - K * r * sin(f1) }
            line.width = width
            line.color = color
          end
        else
          local arc = objs[1]
          local thick = layer.thick * (1 - 0.7 * t)
          arc.start_angle = rp.theta - half
          arc.angle = 2 * half
          arc.min_radius = r - thick
          arc.max_radius = r + thick
          arc.color = color
        end
      end
      i = i + 1
    end
  end
end

---------------------------------------------------------------------------
-- Generator model: spinning torus + glow whose brightness follows the charge
---------------------------------------------------------------------------

local TORUS_FRAMES = 24
local SPIN_SPEED = TORUS_FRAMES / 90      -- one segment step per 1.5 s at full speed
-- Torus sorts just after the building so it is drawn on top of the base.
local TORUS_OFFSET = { 0, 0.05 }

local function frame_now(obj)
  return game.tick * obj.animation_speed + obj.animation_offset
end

-- Changes speed without a visible jump, keeping torus and glow in sync.
local function set_spin(model, speed)
  if model.speed == speed then return end
  for _, obj in pairs({ model.torus, model.torus_glow }) do
    if obj.valid then
      local frame = frame_now(obj)
      obj.animation_speed = speed
      obj.animation_offset = (frame - game.tick * speed) % TORUS_FRAMES
    end
  end
  model.speed = speed
end

local function model_valid(model)
  return model and model.torus.valid and model.torus_glow.valid and model.base_glow.valid
end

function M.create_model(sh)
  local ent = sh.entity
  local target = { entity = ent, offset = TORUS_OFFSET }
  local model = { speed = 0, glow = -1 }
  model.torus = rendering.draw_animation({
    animation = "esd-torus", target = target, surface = ent.surface,
    render_layer = "object", animation_speed = 0,
  })
  model.torus_glow = rendering.draw_animation({
    animation = "esd-torus-glow", target = target, surface = ent.surface,
    render_layer = "higher-object-under", animation_speed = 0,
    light_mode = "glow", tint = tint(0),
  })
  model.base_glow = rendering.draw_sprite({
    sprite = "esd-base-glow", target = ent, surface = ent.surface,
    render_layer = "higher-object-under", light_mode = "glow", tint = tint(0),
  })
  sh.model = model
end

function M.destroy_model(sh)
  local model = sh.model
  if model then
    for _, key in pairs({ "torus", "torus_glow", "base_glow" }) do
      if model[key] and model[key].valid then model[key].destroy() end
    end
  end
  sh.model = nil
end

-- Arcs from the pylon insulators to the torus when the dome is (nearly) fully charged.
-- Model geometry in tiles; heights are drawn at ~0.71 up the screen.
local H = 0.7071
local PYLON_D, BAND_Z, TORUS_R, TORUS_Z = 2.55, 2.55, 1.85, 2.45
local PYLONS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

function M.charge_arcs(sh, charge, powered)
  if not powered or charge < 0.9 then return end
  local tick = game.tick
  if tick < (sh.next_arc or 0) then return end
  sh.next_arc = tick + 20 + math.random(0, 40)
  local ent = sh.entity
  local p = ent.position
  local pylon = PYLONS[math.random(1, 4)]
  local px, py = pylon[1] * PYLON_D, pylon[2] * PYLON_D
  local a = atan2(py, px) + (math.random() - 0.5) * 0.8
  local from = { p.x + px, p.y + py - BAND_Z * H }
  local to = { p.x + TORUS_R * cos(a), p.y + TORUS_R * sin(a) - TORUS_Z * H }
  ent.surface.create_entity({
    name = "esd-zap-beam", position = from, source_position = from, target_position = to, duration = 8,
  })
end

-- charge: 0..1 pooled buffer fill. Spin and glow follow it; off/disabled = dark and still.
function M.update_model(sh, charge, powered)
  if not model_valid(sh.model) then
    M.destroy_model(sh)
    M.create_model(sh)
  end
  local model = sh.model
  local glow = powered and charge or 0
  glow = math.floor(glow * 20 + 0.5) / 20   -- quantize: touch render objects rarely
  if glow ~= model.glow then
    -- Renders clip to near-white; tint the additive glow back to cold blue.
    local blue = { r = 0.55 * glow, g = 0.82 * glow, b = 1.0 * glow, a = glow }
    model.torus_glow.color = blue
    model.base_glow.color = blue
    model.glow = glow
  end
  local speed = powered and charge > 0.02 and SPIN_SPEED * (0.2 + 0.8 * charge) or 0
  speed = math.floor(speed / SPIN_SPEED * 8 + 0.5) / 8 * SPIN_SPEED
  set_spin(model, speed)
end

return M
