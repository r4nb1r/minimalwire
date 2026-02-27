-- Configuration Settings
local MOD_SETTINGS = {
  RADIUS = "minimalwire-radius",
  FULL_NETWORK_MST = "minimalwire-full-network-mst",
  OPERATIONS_PER_TICK = "minimalwire-ops-per-tick",
  MAX_POLES = "minimalwire-max-poles",
  DEBUG = "minimalwire-debug"
}

local function get_mod_setting(setting_name)
  return settings.global[setting_name].value
end

local DEBUG = get_mod_setting(MOD_SETTINGS.DEBUG)
local MAX_OPERATIONS_PER_TICK = get_mod_setting(MOD_SETTINGS.OPERATIONS_PER_TICK)
local RADIUS = get_mod_setting(MOD_SETTINGS.RADIUS)
local FULL_NETWORK_MST = get_mod_setting(MOD_SETTINGS.FULL_NETWORK_MST)
local MAX_POLES = get_mod_setting(MOD_SETTINGS.MAX_POLES)

-- Event Filter (Optimized to react only to electric pole events)
local EVENT_FILTER = {
  { filter = "type", type = "electric-pole" }
}

-- Cache for storing pole data
local pole_cache = {}

-- Helper function to get the size of a table
local function table_size(t)
  local count = 0
  for _ in pairs(t) do
    count = count + 1
  end
  return count
end

-- Helper Functions
local function distance_squared(posA, posB)
  local dx = posA.x - posB.x
  local dy = posA.y - posB.y
  return dx * dx + dy * dy
end

local function get_pole_max_wire_distance(pole)
  if pole and pole.valid then
    -- Check cache first
    if pole_cache[pole.unit_number] and pole_cache[pole.unit_number].max_wire_distance then
      return pole_cache[pole.unit_number].max_wire_distance
    end

    -- Optimization: Directly access prototype data if available
    local prototype = pole.prototype
    if prototype and prototype.get_max_wire_distance then
      local max_wire_distance = prototype.get_max_wire_distance(pole.quality)
      pole_cache[pole.unit_number] = pole_cache[pole.unit_number] or {}
      pole_cache[pole.unit_number].max_wire_distance = max_wire_distance
      return max_wire_distance
    end
  end

  game.print("MinimalWire: Warning: Could not determine max wire distance for pole, using default.")
  return 9 -- Default wire distance
end

-- Subnetwork Gathering Functions
local function gather_connected_poles(start_pole)
  -- Check cache first
  if pole_cache[start_pole.unit_number] and pole_cache[start_pole.unit_number].connected_poles then
    return pole_cache[start_pole.unit_number].connected_poles
  end

  local visited = {}
  local queue = { start_pole }
  visited[start_pole.unit_number] = start_pole

  while #queue > 0 do
    local current_pole = table.remove(queue, 1)
    local connector = current_pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    if connector and connector.valid then
      for _, connection_info in pairs(connector.real_connections) do
        local neighbor_connector = connection_info.target
        if neighbor_connector and neighbor_connector.valid then
          local neighbor_pole = neighbor_connector.owner
          if neighbor_pole and neighbor_pole.valid and not visited[neighbor_pole.unit_number] then
            visited[neighbor_pole.unit_number] = neighbor_pole
            table.insert(queue, neighbor_pole)
          end
        end
      end
    end
  end

  -- Store in cache
  pole_cache[start_pole.unit_number] = pole_cache[start_pole.unit_number] or {}
  pole_cache[start_pole.unit_number].connected_poles = visited

  if DEBUG then
    game.print("Network size: " .. table_size(visited))
  end
  return visited
end

local function gather_nearby_poles(start_pole)
  if not (start_pole and start_pole.valid) then
    return {}
  end

  local cache_key = RADIUS .. "-" .. MAX_POLES
  if pole_cache[start_pole.unit_number] and pole_cache[start_pole.unit_number].nearby_poles and
      pole_cache[start_pole.unit_number].nearby_poles[cache_key] then
    return pole_cache[start_pole.unit_number].nearby_poles[cache_key]
  end

  local surface = start_pole.surface
  local sx, sy = start_pole.position.x, start_pole.position.y

  local initial_RADIUS = math.min(RADIUS, 10)
  local nearby_poles = surface.find_entities_filtered {
    area = { { sx - initial_RADIUS, sy - initial_RADIUS }, { sx + initial_RADIUS, sy + initial_RADIUS } },
    type = "electric-pole"
  }

  local visited = {}
  local pole_count = 1
  visited[start_pole.unit_number] = start_pole

  if #nearby_poles > MAX_POLES then
    table.sort(nearby_poles, function(a, b)
      local dxa, dya = a.position.x - sx, a.position.y - sy
      local dxb, dyb = b.position.x - sx, b.position.y - sy
      return (dxa * dxa + dya * dya) < (dxb * dxb + dyb * dyb)
    end)
  end

  for _, pole in ipairs(nearby_poles) do
    if pole.unit_number ~= start_pole.unit_number then
      local dx, dy = pole.position.x - sx, pole.position.y - sy
      local dist_sq = dx * dx + dy * dy
      if dist_sq <= (RADIUS * RADIUS) then
        if pole_count < MAX_POLES then
          visited[pole.unit_number] = pole
          pole_count = pole_count + 1
        else
          if DEBUG then
            game.print("MinimalWire: Max pole search limit reached, skipping some...")
          end
          break
        end
      end
    end
  end

  if pole_count < MAX_POLES and initial_RADIUS < RADIUS then
    nearby_poles = surface.find_entities_filtered {
      area = { { sx - RADIUS, sy - RADIUS }, { sx + RADIUS, sy + RADIUS } },
      type = "electric-pole"
    }

    for _, pole in ipairs(nearby_poles) do
      if pole.unit_number ~= start_pole.unit_number and not visited[pole.unit_number] then
        local dx, dy = pole.position.x - sx, pole.position.y - sy
        local dist_sq = dx * dx + dy * dy
        if dist_sq <= (RADIUS * RADIUS) and pole_count < MAX_POLES then
          visited[pole.unit_number] = pole
          pole_count = pole_count + 1
        end
      end
    end
  end

  pole_cache[start_pole.unit_number] = pole_cache[start_pole.unit_number] or {}
  pole_cache[start_pole.unit_number].nearby_poles = pole_cache[start_pole.unit_number].nearby_poles or {}
  pole_cache[start_pole.unit_number].nearby_poles[cache_key] = visited

  return visited
end

-- Minimum Spanning Tree (MST) Functions
local function calculate_mst(nodes, edges)
  local parent = {}
  local rank = {}

  for i = 1, #nodes do
    parent[i] = i
    rank[i] = 0
  end

  local function find_root(node_index)
    if parent[node_index] ~= node_index then
      parent[node_index] = find_root(parent[node_index])
    end
    return parent[node_index]
  end

  local function unite_sets(node_index_a, node_index_b)
    local root_a = find_root(node_index_a)
    local root_b = find_root(node_index_b)
    if root_a ~= root_b then
      if rank[root_a] < rank[root_b] then
        parent[root_a] = root_b
      elseif rank[root_a] > rank[root_b] then
        parent[root_b] = root_a
      else
        parent[root_b] = root_a
        rank[root_a] = rank[root_a] + 1
      end
      return true
    end
    return false
  end

  table.sort(edges, function(e1, e2)
    if e1.distance == e2.distance then
      local pole1a = nodes[e1.from]
      local pole1b = nodes[e1.to]
      local pole2a = nodes[e2.from]
      local pole2b = nodes[e2.to]
      local min_y1 = math.min(pole1a.position.y, pole1b.position.y)
      local min_y2 = math.min(pole2a.position.y, pole2b.position.y)
      if min_y1 ~= min_y2 then
        return min_y1 > min_y2
      else
        local min_x1 = math.min(pole1a.position.x, pole1b.position.x)
        local min_x2 = math.min(pole2a.position.x, pole2b.position.x)
        return min_x1 < min_x2
      end
    else
      return e1.distance < e2.distance
    end
  end)

  local mst_edges = {}
  for _, edge in ipairs(edges) do
    if unite_sets(edge.from, edge.to) then
      table.insert(mst_edges, edge)
    end
  end

  return mst_edges
end

-- Subnetwork Rebuilding Function
local function rebuild_mst_for_subnetwork(start_pole, is_removal)
  if not (start_pole and start_pole.valid) then
    if DEBUG then
      game.print("MinimalWire: Warning: Invalid pole, skipping rebuild. If you can recreate this consistently, please report it.")
    end
    return
  end

  local subnetwork
  if FULL_NETWORK_MST and not is_removal then
    subnetwork = gather_connected_poles(start_pole)
  else
    subnetwork = gather_nearby_poles(start_pole)
  end

  for unit_number, pole in pairs(subnetwork) do
    if not (pole and pole.valid) then
      subnetwork[unit_number] = nil
    end
  end

  if DEBUG then
    rendering.clear("minimalwire")
    for _, pole in pairs(subnetwork) do
      if pole and pole.valid then
        rendering.draw_circle {
          color = { r = 0.5, g = 1, b = 0.5 },
          radius = 0.5,
          width = 3,
          filled = false,
          target = pole,
          surface = pole.surface,
          players = { game.players[1] }
        }
      end
    end
  end

  if is_removal then
    subnetwork[start_pole.unit_number] = nil
    if start_pole.valid then
      start_pole.destroy()
    end
  end

  local pole_count = table_size(subnetwork)
  if pole_count < 2 then
    return
  end

  local poles = {}
  local index_map = {}
  do
    local i = 1
    for _, pole in pairs(subnetwork) do
      if pole and pole.valid then
        poles[i] = pole
        index_map[pole.unit_number] = i
        i = i + 1
      end
    end
  end

  local edges = {}
  local num_poles = #poles
  for i = 1, num_poles do
    local poleA = poles[i]
    if poleA and poleA.valid then
      local max_wire_dist_A = get_pole_max_wire_distance(poleA)
      for j = i + 1, num_poles do
        local poleB = poles[j]
        if poleB and poleB.valid then
          local max_wire_dist_B = get_pole_max_wire_distance(poleB)
          local max_wire_dist = math.min(max_wire_dist_A, max_wire_dist_B)
          local distAB_sq = distance_squared(poleA.position, poleB.position)
          if distAB_sq <= max_wire_dist * max_wire_dist then
            local distAB = math.sqrt(distAB_sq)
            table.insert(edges, {
              from = i,
              to = j,
              distance = distAB,
            })
          end
        end
      end
    end
  end

  local mst_edges = calculate_mst(poles, edges)

  if DEBUG then
    game.print(string.format("MST calculation - Poles: %d, Total edges: %d, MST edges: %d",
      #poles,
      #edges,
      #mst_edges
    ))

    local total_mst_length = 0
    for _, edge in ipairs(mst_edges) do
      total_mst_length = total_mst_length + edge.distance
    end

    game.print(string.format("MST stats - Total length: %.2f, Avg edge: %.2f",
      total_mst_length,
      total_mst_length / #mst_edges
    ))
  end

  local mst_edge_set = {}
  for _, edge in ipairs(mst_edges) do
    local a, b = math.min(edge.from, edge.to), math.max(edge.from, edge.to)
    mst_edge_set[a .. "-" .. b] = true
  end

  local function is_edge_part_of_mst(pole_index_a, pole_index_b)
    local a, b = math.min(pole_index_a, pole_index_b), math.max(pole_index_a, pole_index_b)
    return mst_edge_set[a .. "-" .. b] == true
  end

  local disconnect_count = 0
  for _, pole in ipairs(poles) do
    if pole and pole.valid then
      local connector = pole.get_wire_connector(defines.wire_connector_id.pole_copper)
      if connector and connector.valid then
        for _, connection_info in pairs(connector.real_connections) do
          local other_connector = connection_info.target
          if other_connector and other_connector.valid then
            local other_pole = other_connector.owner
            if other_pole and other_pole.valid and subnetwork[other_pole.unit_number] then
              local pole_index_a = index_map[pole.unit_number]
              local pole_index_b = index_map[other_pole.unit_number]
              if not is_edge_part_of_mst(pole_index_a, pole_index_b) then
                table.insert(storage.disconnection_tasks, {
                  pole_connector = connector,
                  other_connector = other_connector
                })
                disconnect_count = disconnect_count + 1
              end
            end
          end
        end
      end
    end
  end

  if DEBUG then
    game.print(string.format("Scheduled tasks - Disconnections: %d, Memory est: %.2f KB",
      disconnect_count,
      (disconnect_count * 50) / 1024
    ))
  end

  for _, edge in ipairs(mst_edges) do
    local poleA = poles[edge.from]
    local poleB = poles[edge.to]
    if poleA and poleA.valid and poleB and poleB.valid then
      local connectorA = poleA.get_wire_connector(defines.wire_connector_id.pole_copper)
      local connectorB = poleB.get_wire_connector(defines.wire_connector_id.pole_copper)
      if connectorA and connectorA.valid and connectorB and connectorB.valid then
        local connectorAConnections = connectorA.real_connections
        local has_connection = false
        for _, connection_info in pairs(connectorAConnections) do
          if connection_info.target == connectorB then
            has_connection = true
            break
          end
        end
        if not has_connection then
          table.insert(storage.connection_tasks, {
            connectorA = connectorA,
            connectorB = connectorB
          })
        end
      end
    end
  end

  if DEBUG then
    game.print(string.format("Scheduled tasks - Connections: %d, Memory est: %.2f KB",
      #storage.connection_tasks,
      (#storage.connection_tasks * 50) / 1024
    ))
  end
end

-- Event Handlers
local function handle_pole_built(event)
  local entity = event.created_entity or event.entity
  if entity and entity.valid then
    rebuild_mst_for_subnetwork(entity, false)
  end
end

local function handle_pole_removed(event)
  local entity = event.created_entity or event.entity
  if entity and entity.valid then
    local dummy_pole = entity.surface.create_entity {
      name = "dummy-hidden-pole",
      position = entity.position,
      force = entity.force,
      create_build_effect_smoke = false
    }
    table.insert(storage.processing_tasks, {
      pole = dummy_pole,
      player_index = event.player_index,
      is_removal = true
    })
  end
end

-- Tick Handler
local function on_tick_handler(event)
  while #storage.processing_tasks > 0 do
    local task = table.remove(storage.processing_tasks)
    if task.pole and task.pole.valid then
      rebuild_mst_for_subnetwork(task.pole, task.is_removal)
    end
  end

  local operations_performed = 0
  while operations_performed < MAX_OPERATIONS_PER_TICK and #storage.disconnection_tasks > 0 do
    local task = table.remove(storage.disconnection_tasks)
    if task.pole_connector and task.other_connector and task.pole_connector.valid and task.other_connector.valid then
      task.pole_connector.disconnect_from(task.other_connector)
    end
    operations_performed = operations_performed + 1
  end

  local connections_performed = 0
  while connections_performed < MAX_OPERATIONS_PER_TICK and #storage.connection_tasks > 0 do
    local task = table.remove(storage.connection_tasks)
    if task.connectorA and task.connectorB and task.connectorA.valid and task.connectorB.valid then
      task.connectorA.connect_to(task.connectorB)
    end
    connections_performed = connections_performed + 1
  end
end

-- Global Storage Initialization
script.on_init(function()
  storage.disconnection_tasks = {}
  storage.connection_tasks = {}
  storage.processing_tasks = {}
  MAX_OPERATIONS_PER_TICK = get_mod_setting(MOD_SETTINGS.OPERATIONS_PER_TICK)
  RADIUS = get_mod_setting(MOD_SETTINGS.RADIUS)
  FULL_NETWORK_MST = get_mod_setting(MOD_SETTINGS.FULL_NETWORK_MST)
  MAX_POLES = get_mod_setting(MOD_SETTINGS.MAX_POLES)
  DEBUG = get_mod_setting(MOD_SETTINGS.DEBUG)
end)

script.on_configuration_changed(function(data)
  storage.disconnection_tasks = storage.disconnection_tasks or {}
  storage.connection_tasks = storage.connection_tasks or {}
  storage.processing_tasks = storage.processing_tasks or {}
  MAX_OPERATIONS_PER_TICK = get_mod_setting(MOD_SETTINGS.OPERATIONS_PER_TICK)
  RADIUS = get_mod_setting(MOD_SETTINGS.RADIUS)
  FULL_NETWORK_MST = get_mod_setting(MOD_SETTINGS.FULL_NETWORK_MST)
  MAX_POLES = get_mod_setting(MOD_SETTINGS.MAX_POLES)
  DEBUG = get_mod_setting(MOD_SETTINGS.DEBUG)
  if DEBUG then
    game.print("MinimalWire: Configution changed, reloading settings...")
    game.print(string.format("MinimalWire: RADIUS: %d, FULL_NETWORK_MST: %s, MAX_POLES: %d, OPERATIONS_PER_TICK: %d",
      RADIUS,
      tostring(FULL_NETWORK_MST),
      MAX_POLES,
      MAX_OPERATIONS_PER_TICK
    ))
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  rendering.clear("minimalwire")
  MAX_OPERATIONS_PER_TICK = get_mod_setting(MOD_SETTINGS.OPERATIONS_PER_TICK)
  RADIUS = get_mod_setting(MOD_SETTINGS.RADIUS)
  FULL_NETWORK_MST = get_mod_setting(MOD_SETTINGS.FULL_NETWORK_MST)
  MAX_POLES = get_mod_setting(MOD_SETTINGS.MAX_POLES)
  DEBUG = get_mod_setting(MOD_SETTINGS.DEBUG)
  if DEBUG then
    game.print("MinimalWire: Configuration changed, reloading settings...")
    game.print(string.format("MinimalWire: RADIUS: %d, FULL_NETWORK_MST: %s, MAX_POLES: %d, OPERATIONS_PER_TICK: %d",
      RADIUS,
      tostring(FULL_NETWORK_MST),
      MAX_POLES,
      MAX_OPERATIONS_PER_TICK
    ))
  end
end)

script.on_event(defines.events.on_built_entity, handle_pole_built, EVENT_FILTER)
script.on_event(defines.events.on_robot_built_entity, handle_pole_built, EVENT_FILTER)
script.on_event(defines.events.on_pre_player_mined_item, handle_pole_removed, EVENT_FILTER)
script.on_event(defines.events.on_robot_pre_mined, handle_pole_removed, EVENT_FILTER)
script.on_event(defines.events.on_entity_died, handle_pole_removed, EVENT_FILTER)
script.on_event(defines.events.on_tick, on_tick_handler)

if DEBUG then
  commands.add_command("poles", "Provides 50 poles", function(event)
    local player = game.players[event.player_index]
    player.insert { name = "medium-electric-pole", count = 50 }
  end)
end
