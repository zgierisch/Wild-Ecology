local EngineTopology = {}

local DIRECTIONS = {
  north = { engineDirection = "up" },
  south = { engineDirection = "down" },
  west = { engineDirection = "left" },
  east = { engineDirection = "right" }
}

local function activeOverworld(game)
  local states = game and game.stack and game.stack.states
  if states then
    for index = #states, 1, -1 do
      if states[index].isOverworld then
        return states[index]
      end
    end
  end
  local overworld = game and game.overworld
  if overworld and overworld.map then
    return overworld
  end
  return nil
end

local function environmentClass(mapModule, definition)
  if not definition then
    return "UNKNOWN"
  end
  if mapModule and type(mapModule.isOutdoor) == "function" then
    local ok, outdoor = pcall(mapModule.isOutdoor, definition)
    if ok then
      return outdoor and "OUTDOOR" or "NON_OUTDOOR"
    end
  end
  if definition.outdoor ~= nil then
    return definition.outdoor and "OUTDOOR" or "NON_OUTDOOR"
  end
  if definition.tileset ~= nil then
    return definition.tileset == "OVERWORLD" and "OUTDOOR" or "NON_OUTDOOR"
  end
  return "UNKNOWN"
end

local function connectionLanding(destination, connection, direction, sourceX, sourceY)
  local destinationWidth = destination.width * 2
  local destinationHeight = destination.height * 2
  local offset = (connection.offset or 0) * 2
  local x, y
  if direction == "north" then
    x, y = sourceX - offset, destinationHeight - 1
  elseif direction == "south" then
    x, y = sourceX - offset, 0
  elseif direction == "west" then
    x, y = destinationWidth - 1, sourceY - offset
  else
    x, y = 0, sourceY - offset
  end
  x = math.max(0, math.min(destinationWidth - 1, x))
  y = math.max(0, math.min(destinationHeight - 1, y))
  return x, y
end

local function connectionCells(map, destination, tileset, connection, direction, mapModule)
  local source = {}
  local usable = {}
  local width = map.widthCells or (map.def and map.def.width and map.def.width * 2) or 0
  local height = map.heightCells or (map.def and map.def.height and map.def.height * 2) or 0
  local horizontal = direction == "north" or direction == "south"
  local count = horizontal and width or height
  for coordinate = 0, count - 1 do
    local sourceX = horizontal and coordinate or (direction == "west" and 0 or width - 1)
    local sourceY = horizontal and (direction == "north" and 0 or height - 1) or coordinate
    source[#source + 1] = { cellX = sourceX, cellY = sourceY }
    if destination and tileset then
      local destinationX, destinationY = connectionLanding(
        destination, connection, direction, sourceX, sourceY
      )
      if map:isWalkableCell(sourceX, sourceY)
        and mapModule.defPassable(destination, tileset, destinationX, destinationY, false) then
        usable[#usable + 1] = {
          cellX = sourceX,
          cellY = sourceY,
          destinationX = destinationX,
          destinationY = destinationY
        }
      end
    end
  end
  return source, usable
end

function EngineTopology.currentMapIdentity(game, mapId)
  local overworld = activeOverworld(game)
  local map = overworld and overworld.map
  if not map or not map.def or (mapId and map.id ~= mapId) then
    return nil
  end
  local data = game and game.data
  local identity = {
    tostring(map),
    tostring(map.def),
    tostring(data),
    tostring(data and data.maps),
    tostring(data and data.tilesets)
  }
  local directions = {}
  for direction in pairs(map.def.connections or {}) do
    directions[#directions + 1] = direction
  end
  table.sort(directions)
  for _, direction in ipairs(directions) do
    local connection = map.def.connections[direction]
    local destination = data and data.maps and data.maps[connection.map]
    local tileset = destination and data.tilesets and data.tilesets[destination.tileset]
    identity[#identity + 1] = table.concat({
      tostring(direction),
      tostring(connection.map),
      tostring(connection.offset),
      tostring(destination),
      tostring(tileset)
    }, ":")
  end
  return table.concat(identity, ":")
end

local function buildTopology(game, mapId, mapModule)
  local overworld = activeOverworld(game)
  local map = overworld and overworld.map
  local data = game and game.data
  mapId = mapId or (map and map.id)
  if not map or not map.def or not data or map.id ~= mapId or not mapModule then
    return nil
  end

  local topology = {
    mapId = map.id,
    width = map.widthCells or (map.def.width and map.def.width * 2),
    height = map.heightCells or (map.def.height and map.def.height * 2),
    environmentClass = environmentClass(mapModule, map.def),
    connections = {},
    warps = {}
  }
  for direction, connection in pairs(map.def.connections or {}) do
    local directionInfo = DIRECTIONS[direction]
    if directionInfo then
      local destination = data.maps and data.maps[connection.map]
      local tileset = destination and data.tilesets and data.tilesets[destination.tileset]
      local source, usable = connectionCells(
        map, destination, tileset, connection, direction, mapModule
      )
      topology.connections[#topology.connections + 1] = {
        direction = direction,
        engineDirection = directionInfo.engineDirection,
        destinationMapId = connection.map,
        destinationWidth = destination and destination.width and destination.width * 2 or nil,
        destinationHeight = destination and destination.height and destination.height * 2 or nil,
        offset = connection.offset or 0,
        resolved = destination ~= nil and tileset ~= nil,
        resolutionReason = destination == nil and "DEST_DEF_MISSING"
          or (tileset == nil and "TILESET_MISSING" or "READY"),
        sourceCells = source,
        usableSourceCells = usable
      }
    end
  end
  table.sort(topology.connections, function(left, right)
    return left.direction < right.direction
  end)

  for index, warp in ipairs(map.def.warps or {}) do
    topology.warps[#topology.warps + 1] = {
      index = index,
      cellX = warp.x,
      cellY = warp.y,
      destinationMapId = warp.destMap,
      destinationWarp = warp.destWarp
    }
  end
  return topology
end

function EngineTopology.probeRuntime(game, mapId, mapModule, mapModuleStatus)
  local overworld = activeOverworld(game)
  local map = overworld and overworld.map
  local data = game and game.data
  local probe = {
    modGame = game ~= nil,
    stack = game ~= nil and game.stack ~= nil,
    overworld = overworld ~= nil,
    runtimeMap = map ~= nil,
    mapDef = map ~= nil and map.def ~= nil,
    gameData = data ~= nil,
    dataMaps = data ~= nil and data.maps ~= nil,
    dataTilesets = data ~= nil and data.tilesets ~= nil,
    mapModuleStatus = mapModuleStatus or (mapModule and "READY" or "UNAVAILABLE"),
    requestedMapId = mapId,
    runtimeMapId = map and map.id or nil,
    topologyStatus = "UNAVAILABLE",
    topologyReason = nil,
    topology = nil
  }

  if not game then
    probe.topologyReason = "MOD_GAME_MISSING"
  elseif not overworld then
    probe.topologyReason = "OVERWORLD_MISSING"
  elseif not map then
    probe.topologyReason = "RUNTIME_MAP_MISSING"
  elseif not map.def then
    probe.topologyReason = "MAP_DEF_MISSING"
  elseif not data then
    probe.topologyReason = "GAME_DATA_MISSING"
  elseif mapId and map.id ~= mapId then
    probe.topologyReason = "MAP_ID_MISMATCH"
  elseif not mapModule then
    probe.topologyReason = "MAP_MODULE_UNAVAILABLE"
  else
    local ok, topology = pcall(buildTopology, game, mapId, mapModule)
    if not ok then
      probe.topologyReason = "TOPOLOGY_BUILD_ERROR"
      probe.topologyError = tostring(topology):gsub("[\r\n]+", " "):sub(1, 160)
    elseif not topology then
      probe.topologyReason = "TOPOLOGY_BUILD_FAILED"
    else
      probe.topologyStatus = "READY"
      probe.topologyReason = "READY"
      probe.topology = topology
      probe.topologyMapId = topology.mapId
      probe.environmentClass = topology.environmentClass
      probe.connectionCount = #(topology.connections or {})
    end
  end
  return probe
end

function EngineTopology.fromRuntime(game, mapId, mapModule)
  return EngineTopology.probeRuntime(game, mapId, mapModule).topology
end

function EngineTopology.probeFromMod(mod, mapId)
  local game = mod and mod.game
  local worldGame = mod and mod.world and mod.world.game
  local ok, mapModule = pcall(require, "src.world.Map")
  local probe = EngineTopology.probeRuntime(
    game,
    mapId,
    ok and mapModule or nil,
    ok and "READY" or "UNAVAILABLE"
  )
  probe.worldGame = worldGame ~= nil
  if not ok then
    probe.mapModuleError = tostring(mapModule):gsub("[\r\n]+", " "):sub(1, 160)
  end
  return probe
end

function EngineTopology.fromMod(mod, mapId)
  return EngineTopology.probeFromMod(mod, mapId).topology
end

function EngineTopology.snapshot(mod, mapId)
  return EngineTopology.fromMod(mod, mapId)
end

function EngineTopology.identityFromMod(mod, mapId)
  return EngineTopology.currentMapIdentity(mod and mod.game, mapId)
end

return EngineTopology