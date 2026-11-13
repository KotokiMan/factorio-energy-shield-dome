data:extend({
  {
    type = "int-setting",
    name = "esd-max-radius-cap",
    setting_type = "runtime-global",
    default_value = 0,
    minimum_value = 0,
    order = "a",
  },
  {
    type = "int-setting",
    name = "esd-max-generators",
    setting_type = "runtime-global",
    default_value = 4,
    minimum_value = 1,
    maximum_value = 8,
    order = "a2",
  },
  {
    type = "bool-setting",
    name = "esd-dome-glow",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "esd-alerts",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c",
  },
})
