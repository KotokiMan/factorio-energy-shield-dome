local shared = require("shared")
local mask_util = require("collision-mask-util")

-- Enemy walkers collide with the barrier layer, so the dome blocks them.
-- Done in final-fixes so units added by other mods are covered too.
for _, kind in pairs({ "unit", "spider-unit" }) do
  for _, proto in pairs(data.raw[kind] or {}) do
    local mask = mask_util.get_mask(proto)
    mask.layers[shared.barrier_layer] = true
    proto.collision_mask = mask
  end
end
