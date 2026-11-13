-- Electric field outside the barrier, and burning enemies that are inside the dome.
local config = require("scripts.config")
local pool = require("scripts.pool")

local M = {}

local PI = math.pi
local sqrt, min, max, ceil = math.sqrt, math.min, math.max, math.ceil
local cos, sin, atan2 = math.cos, math.sin, math.atan2
local WALKER_TYPES = { "unit", "spider-unit" }
local TARGET_TYPES = { "unit", "spider-unit", "unit-spawner", "turret" }
local STRUCTURE = { ["unit-spawner"] = true, ["turret"] = true }
local BEAM = "esd-zap-beam"
local LEGGED = "spider-unit"
local DT = config.update_interval / 60

function M.enemy_forces(force)
  local list = {}
  for _, other in pairs(game.forces) do
    if other ~= force and force.is_enemy(other) then
      list[#list + 1] = other
    end
  end
  return list
end

-- Raw electric damage needed to kill this entity through its resistances; nil if immune.
local function damage_to_kill(target)
  local health = target.health or 0
  local resist = target.prototype.resistances
  resist = resist and resist[config.damage_type]
  if not resist then
    return health + 1
  end
  local percent = resist.percent or 0
  if percent >= 0.999 then
    return nil
  end
  return (health + (resist.decrease or 0)) / (1 - percent) + 1
end

-- Pushes a legged enemy back out beyond the barrier. Returns false if energy ran out.
local function repel(sh, target)
  local tick = game.tick
  local seen = sh.repelled or {}
  sh.repelled = seen
  local id = target.unit_number
  local paid = id and seen[id] and tick < seen[id]
  if not paid then
    if not pool.drain(sh, config.repel_cost * sh.mult) then
      return false
    end
    if id then seen[id] = tick + config.repel_cooldown_ticks end
  end
  local c, p = sh.position, target.position
  local a = atan2(p.y - c.y, p.x - c.x)
  local d = max(sh.radius, 0) + config.repel_margin
  target.teleport({ c.x + cos(a) * d, c.y + sin(a) * d })
  if M.on_repel then M.on_repel(sh, { x = c.x + cos(a) * sh.radius, y = c.y + sin(a) * sh.radius }) end
  return true
end

-- Kills enemy walkers inside `radius` with electric damage (legged ones are pushed out
-- instead), paying from the pool. Returns false if energy ran out or a walker is immune.
function M.burn_inside(sh, radius)
  if radius <= 0 then return true end
  local ent = sh.entity
  local enemies = M.enemy_forces(ent.force)
  if #enemies == 0 then return true end
  local walkers = ent.surface.find_entities_filtered({
    position = sh.position, radius = radius, type = WALKER_TYPES, force = enemies,
  })
  local per_hp = config.burn_hp_multiplier * config.cost_per_hp * sh.mult
  for _, walker in pairs(walkers) do
    if walker.valid and walker.type == LEGGED then
      if not repel(sh, walker) then
        return false
      end
    elseif walker.valid then
      local raw = damage_to_kill(walker)
      if not raw then
        return false -- immune to electricity
      end
      if not pool.drain(sh, raw * per_hp) then
        return false
      end
      local stats = pool.stats(sh)
      stats.dealt = stats.dealt + walker.damage(raw, ent.force, config.damage_type, ent)
      if walker.valid then
        walker.die(ent.force, ent)
      end
      stats.kills = stats.kills + 1
    end
  end
  return true
end

-- Enemies in the ring inner..outer, found with small boxes along the ring instead of
-- scanning the whole disc (matters for domes with a radius of hundreds of tiles).
local function ring_targets(sh, inner, outer, enemies, types)
  local surface = sh.entity.surface
  local cx, cy = sh.position.x, sh.position.y
  local sectors = max(8, ceil(2 * PI * outer / 24))
  local step = 2 * PI / sectors
  local pad = outer * (1 - cos(step / 2)) + 1
  local seen, out = {}, {}
  for i = 0, sectors - 1 do
    local a0, a1 = i * step, (i + 1) * step
    local xs = { inner * cos(a0), inner * cos(a1), outer * cos(a0), outer * cos(a1) }
    local ys = { inner * sin(a0), inner * sin(a1), outer * sin(a0), outer * sin(a1) }
    local found = surface.find_entities_filtered({
      area = {
        { cx + min(xs[1], xs[2], xs[3], xs[4]) - pad, cy + min(ys[1], ys[2], ys[3], ys[4]) - pad },
        { cx + max(xs[1], xs[2], xs[3], xs[4]) + pad, cy + max(ys[1], ys[2], ys[3], ys[4]) + pad },
      },
      type = types or TARGET_TYPES,
      force = enemies,
    })
    for _, e in pairs(found) do
      local key = e.unit_number or (e.position.x .. ":" .. e.position.y)
      if not seen[key] then
        seen[key] = true
        local p = e.position
        local d = sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
        if d >= inner and d <= outer then
          out[#out + 1] = { entity = e, distance = d }
        end
      end
    end
  end
  return out
end

local function zap(sh, target, distance)
  local c, p = sh.position, target.position
  local a = atan2(p.y - c.y, p.x - c.x)
  local from = { c.x + cos(a) * sh.radius, c.y + sin(a) * sh.radius }
  sh.entity.surface.create_entity({
    name = BEAM, position = from, source_position = from, target = target,
    duration = config.zone_beam_ticks,
  })
end

-- Legged enemies near the inner side of the edge are pushed back out every update.
function M.repel_tick(sh)
  -- Forget old push records now and then.
  if sh.repelled and game.tick % 600 == 0 then
    for id, until_tick in pairs(sh.repelled) do
      if game.tick >= until_tick then sh.repelled[id] = nil end
    end
  end
  local ent = sh.entity
  local enemies = M.enemy_forces(ent.force)
  if #enemies == 0 or sh.radius <= 0 then return true end
  local r = sh.radius
  for _, t in pairs(ring_targets(sh, max(0, r - config.repel_band), r + 0.5, enemies)) do
    local target = t.entity
    if target.valid and target.type == LEGGED and t.distance < r then
      if not repel(sh, target) then
        return false
      end
    end
  end
  return true
end

-- Enemy acid streams fly over the barrier ring. A stream entity sits at its shooter, so
-- streams of shooters just outside the edge are destroyed before they land, unless
-- something of ours outside the dome is within the shooter's reach (then it may be the
-- target and the stream flies on). The dome pays by shooter size and ripples at the edge.
-- `absorb(sh, damage, at)` is the shield's absorb function.
local STREAM_TYPES = { "stream" }
local STREAM_SIZE = { { "behemoth", 4 }, { "big", 2 }, { "medium", 1 }, { "small", 0.4 } }

local function stream_hp(name)
  local hp = config.stream_hp
  for _, size in pairs(STREAM_SIZE) do
    if name:find(size[1], 1, true) then
      hp = hp * size[2]
      break
    end
  end
  if name:find("worm", 1, true) then
    hp = hp * config.stream_worm_multiplier
  end
  return hp
end

local function friendly_outside(sh, pos)
  local c, r = sh.position, sh.radius + 1
  for _, e in pairs(sh.entity.surface.find_entities_filtered({
    position = pos, radius = config.stream_reach, force = sh.entity.force,
  })) do
    local p = e.position
    if (p.x - c.x) ^ 2 + (p.y - c.y) ^ 2 > r * r and e.name ~= "esd-barrier" then
      return true
    end
  end
  return false
end

function M.block_streams(sh, absorb)
  local ent = sh.entity
  local enemies = M.enemy_forces(ent.force)
  if #enemies == 0 or sh.radius <= 0 then return end
  local r = sh.radius
  local c = sh.position
  for _, t in pairs(ring_targets(sh, r, r + config.stream_reach, enemies, STREAM_TYPES)) do
    local stream = t.entity
    if stream.valid and not friendly_outside(sh, stream.position) then
      local p = stream.position
      local a = atan2(p.y - c.y, p.x - c.x)
      local hp = stream_hp(stream.name)
      stream.destroy()
      if absorb(sh, hp, { x = c.x + cos(a) * r, y = c.y + sin(a) * r }) < 1 then
        return
      end
    end
  end
end

-- One field pulse. Returns false only if something forces a collapse (it never does
-- today: when the pool runs dry the field just stops for this pulse).
function M.field_tick(sh, width)
  local ent = sh.entity
  local enemies = M.enemy_forces(ent.force)
  if #enemies == 0 or sh.radius <= 0 then return true end
  local r = sh.radius
  local targets = ring_targets(sh, r, r + width, enemies)
  if #targets == 0 then return true end

  local bonus = 1 + ent.force.get_ammo_damage_modifier("tesla")
  local per_hp = config.cost_per_hp * sh.mult
  local reserve = min(sh.field_reserve or config.default_field_reserve, config.max_field_reserve) / 100 * pool.buffer(sh)
  -- Beams go to every n-th target, starting at a rotating offset, so zaps show all round
  -- the dome instead of only on the first sectors of the scan.
  local n = #targets
  local stride = max(1, ceil(n / config.zone_beams_per_update))
  local offset = math.random(0, stride - 1)
  -- Start the pass at a random target too: if the reserve stops it half way, the damage
  -- still lands on a different side each pulse.
  local start = math.random(0, n - 1)
  for i = 1, n do
    local t = targets[(i - 1 + start) % n + 1]
    local target = t.entity
    if target.valid then
      local falloff = 1 - (t.distance - r) / width
      local damage = config.zone_dps * DT * falloff * bonus
      if STRUCTURE[target.type] then
        damage = damage * config.zone_structure_multiplier
      end
      if damage > 0 then
        local cost = damage * per_hp
        if pool.energy(sh) < reserve then
          return true -- only spare energy above the reserve feeds the field
        end
        pool.drain(sh, cost)
        if (i + offset) % stride == 0 then
          zap(sh, target, t.distance)
        end
        local stats = pool.stats(sh)
        stats.dealt = stats.dealt + target.damage(damage, ent.force, config.damage_type, ent)
        if not target.valid then
          stats.kills = stats.kills + 1
        end
      end
    end
  end
  return true
end

return M
