-- All balance numbers in one place. Energy in joules, power in watts, distances in tiles.
return {
  update_interval = 10,        -- ticks between shield updates

  -- Generator
  base_buffer = 5e9,           -- per generator; generators on one dome add up
  input_flow = 500e6,          -- max recharge per generator

  -- Dome energy
  deploy_per_tile = 0.25e6,    -- one-off cost per tile of dome area while growing
  upkeep_per_tile = 3e3,       -- continuous cost per tile of dome area
  cost_per_hp = 40e3,          -- absorbing 1 HP of damage, or dealing 1 HP with the field
  burn_hp_multiplier = 2,      -- burning a unit on the growing front costs damage x this x cost_per_hp
  damage_type = "electric",

  -- Growth
  expand_step = 1,             -- radius growth per update
  charge_threshold = 0.95,     -- pooled buffer fill needed before the dome starts growing
  cooldown_ticks = 15 * 60,    -- pause after a collapse

  -- Radius
  min_radius = 8,
  default_radius = 48,
  base_max_radius = 64,
  radius_per_level = 32,       -- fixed technology levels 1..3 -> 160
  radius_per_infinite_level = 16,
  quality_buffer_bonus = 0.3,  -- +30% buffer per quality level
  quality_input_bonus = 0.2,   -- +20% recharge per quality level (legendary = 1 GW)
  quality_radius_bonus = 4,    -- +4 max radius per quality level (primary generator)
  -- Max radius also scales with sqrt(generators on the dome).

  -- Electric field outside the barrier
  zone_width = 6,
  zone_quality_bonus = 1,      -- +1 tile per quality level of the primary
  max_field_reserve = 95,
  default_field_reserve = 50,  -- % of the pooled buffer the field never spends (per dome, slider)
  zone_dps = 50,               -- at the barrier; falls linearly to 0 at the outer edge (a deterrent, turrets do the killing)
  zone_structure_multiplier = 0.5,
                               -- (the rest is kept for absorbing hits); damage scales with the vanilla
                               -- electric weapons research (tesla bonus), uncapped
  zone_beams_per_update = 6,
  -- Legged enemies (Gleba strafers/stompers) step over the ring like a spidertron over walls:
  -- the dome pushes them back out instead of burning them.
  repel_cost = 25e6,           -- per push
  repel_band = 10,             -- checked every update this deep inside the edge
  repel_margin = 5,            -- pushed this far outside the barrier (into the field)
  repel_cooldown_ticks = 60,
  stream_reach = 20,           -- acid streams of enemies this far outside the edge are stopped
  stream_hp = 30,              -- cost of one stopped stream (medium spitter; small x0.4 .. behemoth x4)
  stream_worm_multiplier = 2,
  stream_scan_ticks = 5,
  stomp_cost_factor = 0.1,     -- legged enemies' leg impacts reaching over the edge onto buildings
                               -- inside cost this share (the ring itself has 90% impact resistance)   -- the same enemy is pushed (and paid for) at most once per second
  zone_beam_ticks = 12,

  structure_margin = 4,        -- growth stops this far from enemy nests and worms
  barrier_spacing = 0.9,       -- distance between ring segments (segments are 1x1)
  intruder_scan_every = 6,     -- stable dome: full-disc intruder scan every N updates (1 s);
                               -- strafer eggs hatch wrigglers inside the dome
  acid_scan_every = 6,         -- acid puddle cleanup every N updates (1 s)
  blocked_retry_every = 18,    -- blocked dome: re-check enemy structures every N updates
  link_check_every = 3,        -- generator linking every N updates

  -- Visuals
  max_ripples = 8,             -- per dome at once
  ripple_ticks = 30,
  alert_cooldown_ticks = 300,  -- "under attack" alert per dome
}
