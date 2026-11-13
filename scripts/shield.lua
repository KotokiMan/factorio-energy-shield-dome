-- Shield generators and their domes.
--
-- Every generator has a role:
--   primary -> owns a dome (centre = this generator) and runs the state machine below
--   support -> sits inside another dome and feeds its energy pool (max 4 generators per dome)
--   idle    -> inside a dome that already has 4 generators; does nothing
--
-- Primary states:
--   charging  -> pooled buffer filling, no dome
--   expanding -> dome grows from the generator, burning enemy units it reaches
--   stable    -> dome holds, barrier ring and electric field are up
--   cooldown  -> after a collapse
--   off       -> switched off by the player
--   disabled  -> not allowed on this surface (see planets.lua)
local shared = require("shared")
local config = require("scripts.config")
local planets = require("scripts.planets")
local render = require("scripts.render")
local pool = require("scripts.pool")
local zone = require("scripts.zone")
local map = require("scripts.map")
local alerts = require("scripts.alerts")
local status = require("scripts.status")

local M = {}

-- Ripple on the edge where a legged enemy is pushed out.
zone.on_repel = function(sh, at)
  render.ripple(sh, at)
  map.hit(sh, at)
end

local PI = math.pi
local sqrt, floor, min, max = math.sqrt, math.floor, math.min, math.max
local SECONDS_PER_UPDATE = config.update_interval / 60
local STRUCTURE_TYPES = { "unit-spawner", "turret" }

-- Generators per dome, including the primary (map setting).
function M.max_generators()
  return settings.global["esd-max-generators"].value
end

local function area(radius)
  return PI * radius * radius
end

local function dist(a, b)
  return sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function is_active(sh)
  return sh.role == "primary" and (sh.state == "expanding" or sh.state == "stable") and sh.radius > 0
end
M.is_active = is_active

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------

function M.init()
  storage.shields = storage.shields or {}
  storage.max_radius = storage.max_radius or {}
  storage.guis = storage.guis or {}
  storage.ripples = storage.ripples or {}
  storage.map_players = storage.map_players or {}
end

function M.on_configuration_changed()
  -- 0.0.1 test builds drew a stats block above the generator; it is a status now.
  for _, entry in pairs(storage.hover or {}) do
    for _, obj in pairs(entry.objects or {}) do
      if obj.valid then obj.destroy() end
    end
  end
  storage.hover = nil
  storage.acid_names = nil
  storage.max_radius = {}
  for _, sh in pairs(storage.shields) do
    sh.retarget = true
  end
end

local function acid_names()
  if not storage.acid_names then
    local names = {}
    for name in pairs(prototypes.get_entity_filtered({ { filter = "type", type = "fire" } })) do
      if name:find("acid", 1, true) then
        names[#names + 1] = name
      end
    end
    storage.acid_names = names
  end
  return storage.acid_names
end

---------------------------------------------------------------------------
-- Radius limits
---------------------------------------------------------------------------

function M.retarget_all()
  for _, sh in pairs(storage.shields) do
    sh.retarget = true
  end
end

function M.recompute_max_radius(force)
  local fixed = 0
  for level = 1, shared.radius_tech_levels do
    local tech = force.technologies[shared.radius_tech_prefix .. level]
    if tech and tech.researched then
      fixed = level
    end
  end
  -- Infinite tech: `level` is the level being researched next.
  local first_infinite = shared.radius_tech_levels + 1
  local infinite = 0
  local tech = force.technologies[shared.radius_tech_prefix .. first_infinite]
  if tech then
    infinite = max(0, tech.level - first_infinite)
  end
  local radius = config.base_max_radius
    + fixed * config.radius_per_level
    + infinite * config.radius_per_infinite_level
  storage.max_radius[force.index] = radius
  for _, sh in pairs(storage.shields) do
    if sh.force_index == force.index then
      sh.retarget = true
    end
  end
  return radius
end

-- Research + primary quality, x sqrt(generators on the dome), capped by the map setting.
function M.max_radius_for(sh)
  local force = sh.entity.force
  local base = (storage.max_radius[force.index] or M.recompute_max_radius(force))
    + (sh.quality_level or 0) * config.quality_radius_bonus
  local radius = floor(base * sqrt(pool.count(sh)))
  local cap = settings.global["esd-max-radius-cap"].value
  if cap > 0 then
    radius = min(radius, cap)
  end
  return max(config.min_radius, radius)
end

local function effective_target(sh)
  return min(sh.target, M.max_radius_for(sh))
end
M.effective_target = effective_target

function M.zone_width(sh)
  return config.zone_width + (sh.quality_level or 0) * config.zone_quality_bonus
end

---------------------------------------------------------------------------
-- Barrier ring
---------------------------------------------------------------------------

local function drop_barrier(sh)
  for _, segment in pairs(sh.barrier) do
    if segment.valid then
      segment.destroy()
    end
  end
  sh.barrier = {}
end

local function build_barrier(sh)
  drop_barrier(sh)
  local ent = sh.entity
  local surface, force = ent.surface, ent.force
  local cx, cy, r = sh.position.x, sh.position.y, sh.radius
  local count = max(8, math.ceil(2 * PI * r / config.barrier_spacing))
  local list = sh.barrier
  for i = 0, count - 1 do
    local a = 2 * PI * i / count
    local segment = surface.create_entity({
      name = shared.barrier,
      position = { cx + r * math.cos(a), cy + r * math.sin(a) },
      force = force,
      create_build_effect_smoke = false,
    })
    if segment then
      list[#list + 1] = segment
    end
  end
end

---------------------------------------------------------------------------
-- Visual sync
---------------------------------------------------------------------------

local function refresh_visuals(sh)
  if sh.radius > 0 then
    render.update_dome(sh)
    map.update_dome(sh, M.zone_width(sh))
  else
    render.destroy_dome(sh)
    map.destroy_dome(sh)
  end
end

---------------------------------------------------------------------------
-- Collapse / switching off
---------------------------------------------------------------------------

local function shut_down(sh, new_state)
  if sh.radius > 0 then
    render.collapse(sh)
  end
  drop_barrier(sh)
  sh.radius = 0
  sh.paused = false
  sh.blocked = false
  sh.state = new_state
  if new_state == "cooldown" then
    sh.cooldown_until = game.tick + config.cooldown_ticks
  end
  refresh_visuals(sh)
end

local function collapse(sh)
  local was_up = sh.radius > 0
  pool.empty(sh)
  shut_down(sh, "cooldown")
  if was_up then
    alerts.collapsed(sh)
  end
end
M.collapse = collapse

---------------------------------------------------------------------------
-- Enemy structures, acid
---------------------------------------------------------------------------

-- The dome stops short of enemy nests and worms instead of wiping them out.
local function structure_limit(sh, target)
  local ent = sh.entity
  local enemies = zone.enemy_forces(ent.force)
  if #enemies == 0 then return target end
  local found = ent.surface.find_entities_filtered({
    position = sh.position, radius = target + config.structure_margin,
    type = STRUCTURE_TYPES, force = enemies,
  })
  local limit = target
  for _, structure in pairs(found) do
    local d = dist(structure.position, sh.position) - config.structure_margin
    if d < limit then
      limit = d
    end
  end
  return max(0, floor(limit))
end

local function clear_acid(sh)
  local names = acid_names()
  if #names == 0 then return end
  local fires = sh.entity.surface.find_entities_filtered({
    position = sh.position, radius = sh.radius, name = names,
  })
  for _, fire in pairs(fires) do
    fire.destroy()
  end
end

---------------------------------------------------------------------------
-- Growth
---------------------------------------------------------------------------

local function become_stable(sh)
  sh.state = "stable"
  sh.paused = false
  build_barrier(sh)
  refresh_visuals(sh)
end

-- Applies a changed target: shrink at once, or (re)compute the growth limit.
-- Returns "grow" if there is room to grow, otherwise settles the dome.
local function apply_target(sh)
  sh.retarget = false
  local target = effective_target(sh)
  if target <= sh.radius then
    sh.blocked = false
    if target < sh.radius then
      sh.radius = target
      become_stable(sh)
    elseif sh.state ~= "stable" then
      become_stable(sh)
    end
    return "settled"
  end
  sh.limit = structure_limit(sh, target)
  sh.blocked = sh.limit < target
  if sh.limit <= sh.radius then
    if sh.radius > 0 and sh.state ~= "stable" then
      become_stable(sh)
    end
    return "settled"
  end
  if sh.state ~= "expanding" then
    drop_barrier(sh)
    sh.state = "expanding"
    refresh_visuals(sh)
  end
  return "grow"
end

local function grow(sh)
  if sh.retarget and apply_target(sh) ~= "grow" then
    return
  end
  local new_radius = min(sh.radius + config.expand_step, sh.limit)
  local cost = config.deploy_per_tile * (area(new_radius) - area(sh.radius)) * sh.mult
  if pool.energy(sh) < cost then
    sh.paused = true
    -- Still no barrier while paused: keep the inside clean.
    if not zone.burn_inside(sh, sh.radius) then
      collapse(sh)
    end
    return
  end
  if not zone.burn_inside(sh, new_radius) or pool.energy(sh) < cost then
    sh.paused = true
    return
  end
  pool.drain(sh, cost)
  sh.paused = false
  sh.radius = new_radius
  if new_radius >= sh.limit then
    become_stable(sh)
  else
    refresh_visuals(sh)
  end
end

local function hold(sh)
  sh.updates = (sh.updates or 0) + 1
  if sh.blocked and sh.updates % config.blocked_retry_every == 0 then
    sh.retarget = true
  end
  if sh.retarget and apply_target(sh) == "grow" then
    return
  end

  if not zone.repel_tick(sh) then
    collapse(sh)
    return
  end
  if sh.field_enabled ~= false and not zone.field_tick(sh, M.zone_width(sh)) then
    collapse(sh)
    return
  end
  if sh.updates % config.intruder_scan_every == 0 and not zone.burn_inside(sh, max(0, sh.radius - 1)) then
    collapse(sh)
    return
  end
  if sh.updates % config.acid_scan_every == 0 then
    clear_acid(sh)
  end
end

---------------------------------------------------------------------------
-- Linking generators into one dome
---------------------------------------------------------------------------

local function unlink(support)
  local primary = storage.shields[support.primary_id]
  if primary then
    for i, id in pairs(primary.supports) do
      if id == support.id then
        table.remove(primary.supports, i)
        primary.retarget = true
        break
      end
    end
  end
  support.primary_id = nil
  support.role = "primary"
  support.state = "charging"
end

-- Domes of other primaries whose radius covers this generator.
local function covering_domes(sh)
  local list = {}
  for _, other in pairs(storage.shields) do
    if other ~= sh and other.role == "primary" and other.radius > 0
      and other.surface_index == sh.surface_index and other.force_index == sh.force_index
      and other.entity.valid and dist(other.position, sh.position) <= other.radius then
      list[#list + 1] = other
    end
  end
  table.sort(list, function(a, b) return a.built_tick < b.built_tick end)
  return list
end

local function update_links()
  -- Limit lowered in the map settings: the newest supporters leave the dome.
  local limit = M.max_generators() - 1
  for _, sh in pairs(storage.shields) do
    if sh.role == "primary" and #sh.supports > limit then
      for i = #sh.supports, limit + 1, -1 do
        local support = storage.shields[sh.supports[i]]
        if support then unlink(support) end
      end
    end
  end
  for _, sh in pairs(storage.shields) do
    if sh.entity.valid then
      if sh.role == "support" then
        local primary = storage.shields[sh.primary_id]
        if not (primary and primary.role == "primary" and primary.entity.valid)
          or dist(primary.position, sh.position) > effective_target(primary) then
          unlink(sh)
        end
      elseif #sh.supports == 0 then
        -- Primary without supporters, or idle: can join a dome that reached it.
        local joined, full = false, false
        for _, dome in pairs(covering_domes(sh)) do
          -- If both domes reach each other, the older one wins.
          local mutual = sh.role == "primary" and sh.radius > 0 and dist(sh.position, dome.position) <= sh.radius
          if not (mutual and sh.built_tick < dome.built_tick) then
            if #dome.supports < M.max_generators() - 1 then
              if sh.role == "primary" and sh.state ~= "charging" and sh.state ~= "off" then
                shut_down(sh, "charging")
              end
              sh.role = "support"
              sh.primary_id = dome.id
              dome.supports[#dome.supports + 1] = sh.id
              dome.retarget = true
              joined = true
              break
            else
              full = true
            end
          end
        end
        if not joined then
          if full and sh.role ~= "idle" then
            if sh.radius > 0 then shut_down(sh, "charging") end
            sh.role = "idle"
          elseif not full and sh.role == "idle" then
            sh.role = "primary"
            sh.state = "charging"
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Per-update tick (primaries)
---------------------------------------------------------------------------

local function update(sh)
  local ent = sh.entity
  local rule = planets.get(ent.surface)
  if not rule.enabled then
    if sh.state ~= "disabled" then
      shut_down(sh, "disabled")
    end
    sh.reason = rule.reason
    return
  end
  sh.reason = nil
  sh.mult = rule.cost_multiplier or 1

  if not sh.enabled then
    if sh.state ~= "off" then
      shut_down(sh, "off")
    end
    return
  end

  if sh.state == "off" or sh.state == "disabled" then
    sh.state = "charging"
  elseif sh.state == "cooldown" then
    if game.tick < sh.cooldown_until then return end
    sh.state = "charging"
  end

  if sh.state == "charging" then
    if pool.energy(sh) < config.charge_threshold * pool.buffer(sh) then return end
    if apply_target(sh) ~= "grow" then return end
  end

  local upkeep = config.upkeep_per_tile * area(sh.radius) * SECONDS_PER_UPDATE * sh.mult
  sh.upkeep_watts = upkeep / SECONDS_PER_UPDATE
  if not pool.drain(sh, upkeep) then
    collapse(sh)
    return
  end

  if sh.state == "expanding" then
    grow(sh)
  else
    hold(sh)
  end
end

function M.update_all()
  storage.link_tick = (storage.link_tick or 0) + 1
  if storage.link_tick % config.link_check_every == 0 then
    update_links()
  end
  for id, sh in pairs(storage.shields) do
    local ent = sh.entity
    if ent.valid then
      if sh.role == "primary" then
        update(sh)
      end
      if storage.shields[id] then
        map.ensure_icon(sh)
        local primary = sh.role == "support" and storage.shields[sh.primary_id] or sh
        local buffer = pool.buffer(primary)
        local powered = sh.enabled and sh.role ~= "idle" and primary.state ~= "disabled"
        local charge = buffer > 0 and pool.energy(primary) / buffer or 0
        render.update_model(sh, charge, powered)
        render.charge_arcs(sh, charge, powered)
        status.update(sh, primary)
        -- Re-clip the outline where it meets neighbouring domes (cheap when nothing changed).
        if is_active(sh) then render.update_dome(sh) end
      end
    else
      M.remove(id)
    end
  end
end

---------------------------------------------------------------------------
-- Damage absorption
---------------------------------------------------------------------------

-- Returns the share of the damage the dome took (1 = all, 0..1 = it broke).
local function absorb(sh, damage, ripple_at, by_enemy, hit_entity, cost_factor)
  local cost = damage * config.cost_per_hp * (sh.mult or 1) * (cost_factor or 1)
  if ripple_at then
    render.ripple(sh, ripple_at)
    map.hit(sh, ripple_at)
  end
  if by_enemy then
    alerts.under_attack(sh, hit_entity)
  end
  local energy = pool.energy(sh)
  local stats = pool.stats(sh)
  if energy >= cost then
    pool.drain(sh, cost)
    stats.absorbed = stats.absorbed + damage
    return 1
  end
  stats.absorbed = stats.absorbed + damage * energy / cost
  collapse(sh)
  return energy / cost
end

-- Point on the dome edge where a hit visually lands.
local function edge_point(sh, target_pos, cause)
  local c, r = sh.position, sh.radius
  local from = target_pos
  if cause and cause.valid and cause.surface_index == sh.surface_index then
    local p = cause.position
    if (p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 > r * r then
      from = p
    end
  end
  local dx, dy = from.x - c.x, from.y - c.y
  local len = sqrt(dx * dx + dy * dy)
  if len < 0.5 then
    return target_pos
  end
  return { x = c.x + dx / len * r, y = c.y + dy / len * r }
end

local function covering_shield(surface_index, force_index, pos)
  local best, best_d2
  for _, sh in pairs(storage.shields) do
    if sh.surface_index == surface_index and sh.force_index == force_index and is_active(sh) then
      local d2 = (pos.x - sh.position.x) ^ 2 + (pos.y - sh.position.y) ^ 2
      if d2 <= sh.radius * sh.radius and (not best_d2 or d2 < best_d2) then
        best, best_d2 = sh, d2
      end
    end
  end
  return best
end

local function barrier_owner(segment)
  local pos, si, fi = segment.position, segment.surface_index, segment.force_index
  for _, sh in pairs(storage.shields) do
    if sh.surface_index == si and sh.force_index == fi and sh.role == "primary" and sh.state == "stable" then
      if math.abs(dist(pos, sh.position) - sh.radius) < 1.5 then
        return sh
      end
    end
  end
end

-- Enemy acid streams crossing the barrier (called every few ticks).
function M.block_streams_all()
  for _, sh in pairs(storage.shields) do
    if sh.role == "primary" and sh.state == "stable" and sh.radius > 0 and sh.entity.valid then
      zone.block_streams(sh, function(dome, damage, at)
        return absorb(dome, damage, at, true, nil)
      end)
    end
  end
end

function M.on_damaged(event)
  local ent = event.entity
  if not (ent and ent.valid) then return end
  local damage = event.final_damage_amount
  if damage <= 0 or not next(storage.shields) then return end

  local cause = event.cause
  local by_enemy = cause and cause.valid and ent.force.is_enemy(cause.force) or false

  if ent.name == shared.barrier then
    ent.health = ent.max_health
    -- Everything that hits the dome costs energy (enemy attacks, our own bombs
    -- going off nearby), except our own fire, so burning ground at the edge
    -- does not drain the shield forever.
    local own_fire = not by_enemy and event.damage_type.name == "fire"
      and (not (cause and cause.valid) or cause.force == ent.force)
    if not own_fire then
      local sh = barrier_owner(ent)
      if sh then
        if by_enemy then
          -- An enemy area attack (acid splash, stomp) is paid like vanilla walls: once for
          -- every barrier tile it covers, so the cost does not depend on segment spacing.
          local tick = game.tick
          if sh.hit_tick ~= tick then
            sh.hit_tick, sh.hit_seen = tick, {}
          end
          local p = ent.position
          local key = (cause.unit_number or 0) .. ":" .. math.floor(p.x) .. ":" .. math.floor(p.y)
          local paid = sh.hit_seen[key] or 0
          if damage > paid then
            sh.hit_seen[key] = damage
            absorb(sh, damage - paid, ent.position, true, ent)
          end
        else
          absorb(sh, damage, ent.position, false, ent)
        end
      end
    end
    return
  end

  local sh = covering_shield(ent.surface_index, ent.force_index, ent.position)
  if not sh then return end
  -- Legs of Gleba stompers reaching over the edge: the dome takes it at a discount.
  local factor = (by_enemy and cause.type == "spider-unit" and event.damage_type.name == "impact")
    and config.stomp_cost_factor or 1
  local share = absorb(sh, damage, edge_point(sh, ent.position, cause), by_enemy, ent, factor)
  if share > 0 and ent.valid then
    -- Health is clamped at 0, so on overkill the pre-hit health is unknown;
    -- it was at most min(max_health, damage).
    local health = ent.health
    local before = health > 0 and (health + damage) or min(ent.max_health, damage)
    local after = before - damage * (1 - share)
    if after > 0 then
      ent.health = after
    end
  end
end

---------------------------------------------------------------------------
-- Lifecycle and settings
---------------------------------------------------------------------------

function M.add(entity, tags)
  local id = entity.unit_number
  local quality_level = entity.quality.level
  entity.electric_buffer_size = config.base_buffer * (1 + quality_level * config.quality_buffer_bonus)
  entity.input_flow_limit = config.input_flow * (1 + quality_level * config.quality_input_bonus) / 60  -- J per tick
  local sh = {
    id = id,
    entity = entity,
    position = entity.position,
    surface_index = entity.surface_index,
    force_index = entity.force_index,
    quality_level = quality_level,
    built_tick = game.tick,
    role = "primary",
    supports = {},
    state = "charging",
    radius = 0,
    target = config.default_radius,
    field_reserve = config.default_field_reserve,
    field_enabled = true,
    enabled = true,
    barrier = {},
    mult = 1,
    upkeep_watts = 0,
  }
  if tags then
    if tags.esd_target then sh.target = tags.esd_target end
    if tags.esd_enabled ~= nil then sh.enabled = tags.esd_enabled end
    if tags.esd_field_reserve then sh.field_reserve = min(tags.esd_field_reserve, config.max_field_reserve) end
    if tags.esd_field_enabled ~= nil then sh.field_enabled = tags.esd_field_enabled end
  end
  storage.shields[id] = sh
  script.register_on_object_destroyed(entity)
  return sh
end

function M.remove(id)
  local sh = storage.shields[id]
  if not sh then return end
  drop_barrier(sh)
  render.destroy_dome(sh)
  render.destroy_model(sh)
  map.destroy_all(sh)
  storage.shields[id] = nil

  if sh.role == "support" then
    local primary = storage.shields[sh.primary_id]
    if primary then
      for i, sid in pairs(primary.supports) do
        if sid == id then
          table.remove(primary.supports, i)
          break
        end
      end
      primary.retarget = true
    end
  elseif sh.role == "primary" and #sh.supports > 0 then
    -- The oldest supporter takes over and redeploys from its own position.
    local heirs = {}
    for _, sid in pairs(sh.supports) do
      local s = storage.shields[sid]
      if s and s.entity.valid then heirs[#heirs + 1] = s end
    end
    table.sort(heirs, function(a, b) return a.built_tick < b.built_tick end)
    local heir = heirs[1]
    if heir then
      heir.role = "primary"
      heir.primary_id = nil
      heir.state = "charging"
      heir.radius = 0
      heir.supports = {}
      heir.target = sh.target
      heir.enabled = sh.enabled
      heir.field_reserve = sh.field_reserve
      heir.field_enabled = sh.field_enabled
      heir.stats = sh.stats
      for i = 2, #heirs do
        heirs[i].primary_id = heir.id
        heir.supports[#heir.supports + 1] = heirs[i].id
      end
      if sh.radius > 0 then
        alerts.collapsed(heir)
      end
    end
  end
end

function M.get(entity)
  return entity and entity.valid and storage.shields[entity.unit_number]
end

-- Settings are always applied to the dome's primary.
function M.primary_of(sh)
  if sh.role == "support" then
    return storage.shields[sh.primary_id] or sh
  end
  return sh
end

function M.set_target(sh, radius)
  sh = M.primary_of(sh)
  sh.target = max(config.min_radius, floor(radius))
  sh.retarget = true
end

function M.set_field_reserve(sh, percent)
  sh = M.primary_of(sh)
  sh.field_reserve = max(0, min(config.max_field_reserve, floor(percent + 0.5)))
end

function M.set_field_enabled(sh, enabled)
  sh = M.primary_of(sh)
  sh.field_enabled = enabled
end

function M.set_enabled(sh, enabled)
  sh = M.primary_of(sh)
  sh.enabled = enabled
end

function M.copy_settings(from, to)
  from = M.primary_of(from)
  to.target = from.target
  to.enabled = from.enabled
  to.field_reserve = from.field_reserve
  to.field_enabled = from.field_enabled
  to.retarget = true
end

function M.tags(sh)
  sh = M.primary_of(sh)
  return { esd_target = sh.target, esd_enabled = sh.enabled, esd_field_reserve = sh.field_reserve, esd_field_enabled = sh.field_enabled }
end

return M
