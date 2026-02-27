data:extend({
    {
      -- Hidden electric pole used for keeping track of a removed pole
      type = "electric-pole",
      name = "dummy-hidden-pole",
      icon = "__base__/graphics/icons/small-electric-pole.png", 
      icon_size = 64,
  
      -- Flags to keep it off-map and unselectable:
      flags = {"placeable-off-grid", "not-on-map", "not-blueprintable"},
      selectable_in_game = false,
      minable = nil,                -- so it can't be mined
      max_health = 100,
      corpse = "small-electric-pole-remnants",
  
      -- No collision or selection box:
      collision_box = {{0, 0}, {0, 0}},
      selection_box = {{0, 0}, {0, 0}},
      drawing_box = {{0, 0}, {0, 0}},  -- so there's no visible bounding

      -- Don't want it distributing power or connecting wires automatically:
      maximum_wire_distance = 0,
      supply_area_distance = 0,

      -- Needs at least one connection point, even if it won't be used:
      connection_points = {
        {
          wire = { copper = {0, -0.5} },
            shadow = { copper = {0, -0.5} }
        }
      },
    }
  })
  