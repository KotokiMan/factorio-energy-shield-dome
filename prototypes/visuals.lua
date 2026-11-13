local shared = require("shared")
local layout = require("prototypes.layout")

local G = "__energy-shield-dome__/graphics/"

local function torus_animation(name, file, additive)
  return {
    type = "animation",
    name = name,
    filename = G .. "entity/" .. file,
    width = layout.torus.width,
    height = layout.torus.height,
    shift = layout.torus.shift,
    scale = layout.torus.scale,
    frame_count = layout.torus.frame_count,
    line_length = layout.torus.line_length,
    blend_mode = additive and "additive" or nil,
  }
end

-- Field zaps: the vanilla tesla beam look, without its damage (the script deals the damage).
local zap = table.deepcopy(data.raw["beam"]["chain-tesla-turret-beam-start"])
zap.name = "esd-zap-beam"
zap.action = nil
zap.action_triggered_automatically = false
zap.hidden = true

data:extend({
  torus_animation("esd-torus", "torus.png", false),
  torus_animation("esd-torus-glow", "torus-glow.png", true),
  {
    type = "sprite",
    name = "esd-base-glow",
    filename = G .. "entity/base-glow.png",
    width = layout.base.width,
    height = layout.base.height,
    shift = layout.base.shift,
    scale = layout.base.scale,
    blend_mode = "additive",
  },
  {
    -- Soft glow inside the dome silhouette (ground circle + north half-ellipse).
    -- 1024 px wide = 2r at scale r/16; smooth gradient, so scaling up stays clean.
    type = "sprite",
    name = "esd-dome-glow",
    filename = G .. "dome-glow.png",
    width = 1024,
    height = 1140,
    flags = { "no-crop" },
  },
  zap,
  {
    type = "shortcut",
    name = shared.map_shortcut,
    order = "z[esd-map]",
    action = "lua",
    toggleable = true,
    associated_control_input = shared.map_input,
    icon = G .. "icons/energy-shield-generator.png",
    icon_size = 64,
    small_icon = G .. "icons/energy-shield-generator.png",
    small_icon_size = 64,
  },
  {
    type = "custom-input",
    name = shared.map_input,
    key_sequence = "CONTROL + SHIFT + D",
    consuming = "none",
  },
})
