data:extend({
    {
      type = "int-setting",
      name = "minimalwire-radius",
      setting_type = "runtime-global",
      default_value = 42,
      minimum_value = 1,
      maximum_value = 1000,
      order = "a",
      localised_name = "MST (Minimum Spanning Tree) Generation Radius",
      localised_description = "Defines how far (in tiles) around a newly placed pole to search for other poles."
    },
    {
      type = "int-setting",
      name = "minimalwire-max-poles",
      setting_type = "runtime-global",
      default_value = 30,
      minimum_value = 1,
      maximum_value = 1000,
      order = "a2",
      localised_name = "Maximum Poles in Radius",
      localised_description = "Maximum number of poles to include in a local network rebuild."
    },
    {
      type = "bool-setting",
      name = "minimalwire-full-network-mst",
      setting_type = "runtime-global",
      default_value = false,
      order = "b",
      localised_name = "Full-Network MST Generation (READ TOOLTIP)",
      localised_description = "If true, attempt to create a single MST for the entire network (of connections) instead of just nearby poles. This may be LAGGY, but is useful to convert inefficient networks."
    },
    {
      type = "int-setting",
      name = "minimalwire-ops-per-tick",
      setting_type = "runtime-global",
      default_value = 10,
      minimum_value = 1,
      maximum_value = 1000,
      order = "c",
      localised_name = "Operations per Tick",
      localised_description = "How many wire operations to process each tick (higher = faster but can cause lag spikes)."
    },
    {
      type = "bool-setting",
      name = "minimalwire-debug",
      setting_type = "runtime-global",
      default_value = false,
      order = "z",
      localised_name = "Debug Mode",
      localised_description = "Enable debug mode (prints debug messages to the console)."
    }
  })
  
