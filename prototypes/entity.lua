local shared = require("shared")
local config = require("scripts.config")

local layout = require("prototypes.layout")

local G = "__energy-shield-dome__/graphics/entity/"
local reactor = data.raw["reactor"]["nuclear-reactor"]

-- Static part of the model. The spinning torus and the glow are drawn by script
-- (scripts/render.lua) so their brightness can follow the buffer charge.
local picture = {
  layers = {
    {
      filename = G .. "base.png",
      width = layout.base.width, height = layout.base.height,
      shift = layout.base.shift, scale = layout.base.scale,
    },
    {
      filename = G .. "shadow.png",
      width = layout.shadow.width, height = layout.shadow.height,
      shift = layout.shadow.shift, scale = layout.shadow.scale,
      draw_as_shadow = true,
    },
  },
}

-- Own wreck: vanilla remnant settings, our picture and 7x7 size.
local remnants = table.deepcopy(data.raw["corpse"]["nuclear-reactor-remnants"])
remnants.name = "energy-shield-generator-remnants"
remnants.icon = "__energy-shield-dome__/graphics/icons/energy-shield-generator.png"
remnants.icons = nil
remnants.selection_box = { { -3.5, -3.5 }, { 3.5, 3.5 } }
remnants.tile_width = 7
remnants.tile_height = 7
remnants.animation = {
  filename = G .. "remnants.png",
  width = layout.remnants.width, height = layout.remnants.height,
  shift = layout.remnants.shift, scale = layout.remnants.scale,
  frame_count = 1, direction_count = 1,
}
data:extend({ remnants })

local function joules(value)
  return string.format("%.0fJ", value)
end

local function watts(value)
  return string.format("%.0fW", value)
end

data:extend({
  {
    type = "electric-energy-interface",
    name = shared.generator,
    icon = "__energy-shield-dome__/graphics/icons/energy-shield-generator.png",
    flags = { "placeable-player", "player-creation" },
    minable = { mining_time = 2, result = shared.generator },
    max_health = 2000,
    corpse = "energy-shield-generator-remnants",
    dying_explosion = "nuclear-reactor-explosion",
    resistances = {
      { type = "fire", percent = 90 },
      { type = "acid", percent = 50 },
      { type = "explosion", percent = 50 },
    },
    collision_box = { { -3.3, -3.3 }, { 3.3, 3.3 } },
    selection_box = { { -3.5, -3.5 }, { 3.5, 3.5 } },
    damaged_trigger_effect = reactor.damaged_trigger_effect,
    surface_conditions = { { property = "gravity", min = 0.1 } },
    gui_mode = "none",
    energy_source = {
      type = "electric",
      usage_priority = "secondary-input",
      buffer_capacity = joules(config.base_buffer),
      input_flow_limit = watts(config.input_flow),
      output_flow_limit = "0W",
      drain = "0W",
    },
    energy_production = "0W",
    energy_usage = "0W",
    picture = picture,
    open_sound = reactor.open_sound,
    close_sound = reactor.close_sound,
    impact_category = "metal-large",
  },
  {
    -- Invisible ring segment. Only enemy units collide with it; players, vehicles,
    -- trains, robots and our projectiles pass through.
    type = "simple-entity-with-force",
    name = shared.barrier,
    hidden = true,
    flags = {
      "not-on-map", "not-blueprintable", "not-deconstructable", "not-rotatable",
      "placeable-off-grid", "no-copy-paste", "not-upgradable", "not-in-kill-statistics",
      "not-selectable-in-game",
    },
    max_health = 100000,
    -- Gleba stompers crush whatever their legs land on (impact damage). Crossing the ring
    -- would otherwise cost more than any wave; the shield pays a tenth of it.
    resistances = { { type = "impact", percent = 90 } },
    collision_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
    collision_mask = { layers = { [shared.barrier_layer] = true } },
    is_military_target = true,
    alert_when_damaged = false,
    create_ghost_on_death = false,
    picture = { filename = "__core__/graphics/empty.png", size = 1 },
  },
  {
    type = "custom-input",
    name = shared.open_input,
    key_sequence = "",
    linked_game_control = "open-gui",
    consuming = "none",
  },
})
