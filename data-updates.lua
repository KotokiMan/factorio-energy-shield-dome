-- Show the dome's electric field in vanilla electric weapon damage research: every tech
-- that boosts tesla damage also lists the field bonus with the generator icon.
for _, tech in pairs(data.raw.technology) do
  local extra = {}
  for _, effect in pairs(tech.effects or {}) do
    if effect.type == "ammo-damage" and effect.ammo_category == "tesla" then
      extra[#extra + 1] = {
        type = "nothing",
        icon = "__energy-shield-dome__/graphics/icons/energy-shield-generator.png",
        icon_size = 64,
        effect_description = { "modifier-description.esd-field-damage", tostring(math.floor(effect.modifier * 100 + 0.5)) },
      }
    end
  end
  for _, effect in pairs(extra) do
    table.insert(tech.effects, effect)
  end
end
