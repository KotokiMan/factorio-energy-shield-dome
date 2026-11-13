local shared = require("shared")
local config = require("scripts.config")

local packs = {
  { "automation-science-pack", 1 },
  { "logistic-science-pack", 1 },
  { "chemical-science-pack", 1 },
  { "military-science-pack", 1 },
  { "utility-science-pack", 1 },
  { "electromagnetic-science-pack", 1 },
}

local icon = { icon = "__energy-shield-dome__/graphics/icons/energy-shield-dome-tech.png", icon_size = 256 }
-- Radius upgrades: same picture with the vanilla "range" corner badge.
local radius_icons = {
  { icon = icon.icon, icon_size = icon.icon_size },
  {
    icon = "__core__/graphics/icons/technology/constants/constant-range.png",
    icon_size = 128, scale = 0.5, shift = { 50, 50 }, floating = true,
  },
}

local techs = {
  {
    type = "technology",
    name = shared.tech,
    icon = icon.icon,
    icon_size = icon.icon_size,
    prerequisites = { "electromagnetic-science-pack", "utility-science-pack", "military-science-pack" },
    effects = { { type = "unlock-recipe", recipe = shared.generator } },
    unit = { count = 1500, ingredients = packs, time = 60 },
  },
}

local function radius_tech(level, bonus, unit, extra)
  local tech = {
    type = "technology",
    name = shared.radius_tech_prefix .. level,
    localised_name = { "technology-name.esd-radius" },
    localised_description = { "technology-description.esd-radius" },
    icons = radius_icons,
    upgrade = true,
    prerequisites = { level == 1 and shared.tech or shared.radius_tech_prefix .. (level - 1) },
    effects = {
      {
        type = "nothing",
        effect_description = { "esd-tech.radius-effect", tostring(bonus) },
        icon = icon.icon,
        icon_size = icon.icon_size,
      },
    },
    unit = unit,
  }
  for k, v in pairs(extra or {}) do
    tech[k] = v
  end
  return tech
end

-- Fixed levels.
for level = 1, shared.radius_tech_levels do
  techs[#techs + 1] = radius_tech(level, config.radius_per_level,
    { count = 1000 * level, ingredients = packs, time = 60 })
end

-- Infinite level: the real limiter is upkeep, which grows with the dome area.
local first_infinite = shared.radius_tech_levels + 1
techs[#techs + 1] = radius_tech(first_infinite, config.radius_per_infinite_level,
  {
    count_formula = string.format("2^(L-%d)*4000", first_infinite),
    ingredients = packs,
    time = 60,
  },
  { max_level = "infinite" })

data:extend(techs)
