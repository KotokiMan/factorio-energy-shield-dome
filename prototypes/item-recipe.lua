local shared = require("shared")

data:extend({
  {
    type = "item",
    name = shared.generator,
    icon = "__energy-shield-dome__/graphics/icons/energy-shield-generator.png",
    subgroup = "defensive-structure",
    order = "z[energy-shield-generator]",
    place_result = shared.generator,
    stack_size = 1,
    weight = 1000000, -- 1 t: exactly one per rocket
  },
  {
    type = "recipe",
    name = shared.generator,
    enabled = false,
    categories = { "electromagnetics" },
    -- Only Fulgora's magnetic field allows assembling the emitter core.
    surface_conditions = { { property = "magnetic-field", min = 99 } },
    energy_required = 60,
    ingredients = {
      { type = "item", name = "supercapacitor", amount = 50 },
      { type = "item", name = "superconductor", amount = 50 },
      { type = "item", name = "processing-unit", amount = 100 },
      { type = "item", name = "refined-concrete", amount = 100 },
      { type = "item", name = "accumulator", amount = 20 },
    },
    results = { { type = "item", name = shared.generator, amount = 1 } },
  },
})
