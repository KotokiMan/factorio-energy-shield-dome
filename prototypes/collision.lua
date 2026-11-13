local shared = require("shared")

-- Layer used only by barrier segments and (via data-final-fixes) by enemy units.
data:extend({
  { type = "collision-layer", name = shared.barrier_layer },
})
