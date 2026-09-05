local Config = require("src.core.config")
local EngineTopology = require("src.world.engine_topology")

local WorldSemantics = {}

local cache = nil
local semanticsGeneration = 0
local lastProductionProbe = nil

local function key(x, y)
  return tostring(x) .. ":" .. tostring(y)
end

local function edgeKey(fromX, fromY, toX, toY)
  return key(fromX, fromY) .. ">" .. key(toX, toY)
end

local function baseCell(char)
  if char == "." then
    return { kind = "GROUND", walkable = true, validLanding = true, blocksLineOfSight = false }
  elseif char == "~" then
    return { kind = "WATER", walkable = false, swimmable = true, validLanding = false, blocksLineOfSight = false }
  elseif char == "+" then
    return { kind = "MAP_TRANSITION", walkable = false, validLanding = false, blocksLineOfSight = false }
  end
  return { kind = "UNKNOWN_BARRIER", walkable = false, validLanding = false, blocksLineOfSight = true }
end

local function copyRecord(record)
  local copy = {}
  for name, value in pairs(record or {}) do
    copy[name] = value
  end
  return copy
end

local function configuredMapKind(mapId)
  local configured = Config.worldSemantics and Config.worldSemantics[mapId]
  return configured and configured.mapKind or "OTHER"
end

local function transitionKind(environmentClass, destinationKind, topologyKind)
  if topologyKind == "CONNECTION" and environmentClass == "OUTDOOR" then
    return "OVERWORLD_EXIT"
  elseif destinationKind == "CAVE" then
    return "CAVE_ENTRANCE"
  elseif destinationKind == "INTERIOR" then
    return "BUILDING_ENTRANCE"
  elseif topologyKind == "CONNECTION" then
    return "MAP_CONNECTION"
  end
  return "MAP_WARP"
end

local function derivedTransitions(environmentClass, topology)
  local transitions = {}
  for _, connection in ipairs(topology and topology.connections or {}) do
    local destinationKind = configuredMapKind(connection.destinationMapId)
    local kind = transitionKind(environmentClass, destinationKind, "CONNECTION")
    connection.transitionKind = kind
    for _, cell in ipairs(connection.usableSourceCells or connection.sourceCells or {}) do
      transitions[key(cell.cellX, cell.cellY)] = {
        kind = kind,
        topologyKind = "CONNECTION",
        direction = connection.direction,
        destinationMapId = connection.destinationMapId,
        destinationMapKind = destinationKind,
        destinationX = cell.destinationX,
        destinationY = cell.destinationY,
        offset = connection.offset
      }
    end
  end
  for _, warp in ipairs(topology and topology.warps or {}) do
    local destinationKind = configuredMapKind(warp.destinationMapId)
    transitions[key(warp.cellX, warp.cellY)] = {
      kind = transitionKind(environmentClass, destinationKind, "WARP"),
      topologyKind = "WARP",
      destinationMapId = warp.destinationMapId,
      destinationMapKind = destinationKind,
      destinationWarp = warp.destinationWarp,
      warpIndex = warp.index
    }
  end
  return transitions
end

local function connectionCellSets(topology)
  local sourceCells = {}
  local usableSourceCells = {}
  for _, connection in ipairs(topology and topology.connections or {}) do
    for _, cell in ipairs(connection.sourceCells or {}) do
      sourceCells[key(cell.cellX, cell.cellY)] = true
    end
    for _, cell in ipairs(connection.usableSourceCells or {}) do
      usableSourceCells[key(cell.cellX, cell.cellY)] = true
    end
  end
  return sourceCells, usableSourceCells
end

function WorldSemantics.fromOverview(overview, overrides, topology)
  if not overview or type(overview.rows) ~= "table" then
    return nil
  end
  local mapKind = overrides and overrides.mapKind or "OTHER"
  local environmentClass = topology and topology.environmentClass or "UNKNOWN"
  if overrides and overrides.environmentClass then
    environmentClass = overrides.environmentClass
  elseif mapKind == "CAVE" or mapKind == "INTERIOR" then
    environmentClass = "NON_OUTDOOR"
  end
  local transitions = derivedTransitions(environmentClass, topology)
  local connectionSourceCells, usableConnectionSourceCells = connectionCellSets(topology)
  for transitionKey, transition in pairs(overrides and overrides.transitions or {}) do
    transitions[transitionKey] = copyRecord(transition)
  end
  return {
    mapId = overview.mapId,
    mapKind = mapKind,
    environmentClass = environmentClass,
    width = overview.width or #(overview.rows[1] or ""),
    height = overview.height or #overview.rows,
    rows = overview.rows,
    cellOverrides = overrides and overrides.cells or {},
    edgeOverrides = overrides and overrides.edges or {},
    transitions = transitions,
    connectionSourceCells = connectionSourceCells,
    usableConnectionSourceCells = usableConnectionSourceCells,
    connections = topology and topology.connections or {},
    warps = topology and topology.warps or {},
    topology = topology
  }
end

local function shortError(value)
  return tostring(value):gsub("[\r\n]+", " "):sub(1, 160)
end

local function probeFromMod(mod, mapId, overrides, allowCache)
  local runtimeIdentity = EngineTopology.identityFromMod(mod, mapId)
  local topologyProbe = EngineTopology.probeFromMod(mod, mapId)
  local probe = {
    mapId = mapId,
    modWorld = mod ~= nil and mod.world ~= nil,
    mapOverviewStatus = "NOT_RUN",
    semanticsStatus = "UNAVAILABLE",
    semanticsReason = nil,
    topologyProbe = topologyProbe,
    topologyStatus = topologyProbe.topologyStatus,
    topologyReason = topologyProbe.topologyReason,
    topologyMapId = topologyProbe.topologyMapId,
    semantics = nil
  }

  if allowCache and not overrides and cache and cache.mapId == mapId
    and runtimeIdentity ~= nil and cache.runtimeIdentity == runtimeIdentity then
    probe.mapOverviewStatus = "NOT_PROBED_CACHE"
    probe.semanticsStatus = "READY"
    probe.semanticsReason = "CACHE_HIT"
    probe.semantics = cache.semantics
    return probe
  end
  local world = mod and mod.world
  if not world then
    probe.mapOverviewStatus = "UNAVAILABLE"
    probe.semanticsReason = "MOD_WORLD_MISSING"
    return probe
  elseif type(world.mapOverview) ~= "function" then
    probe.mapOverviewStatus = "UNAVAILABLE"
    probe.semanticsReason = "MAP_OVERVIEW_UNAVAILABLE"
    return probe
  end
  local ok, overview = pcall(function()
    return world:mapOverview()
  end)
  if not ok then
    probe.mapOverviewStatus = "ERROR"
    probe.mapOverviewError = shortError(overview)
    probe.semanticsReason = "MAP_OVERVIEW_ERROR"
    return probe
  elseif overview == nil then
    probe.mapOverviewStatus = "NIL"
    probe.semanticsReason = "MAP_OVERVIEW_NIL"
    return probe
  elseif type(overview) ~= "table" then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_INVALID"
    return probe
  end

  probe.overviewMapId = overview.mapId
  probe.overviewWidth = overview.width
  probe.overviewHeight = overview.height
  probe.overviewRows = type(overview.rows) == "table" and #overview.rows or nil
  if mapId and overview.mapId and overview.mapId ~= mapId then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_MAP_ID_MISMATCH"
    return probe
  elseif overview.rows == nil then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_ROWS_MISSING"
    return probe
  elseif type(overview.rows) ~= "table" then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_ROWS_INVALID"
    return probe
  elseif overview.width ~= nil and type(overview.width) ~= "number" then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_WIDTH_INVALID"
    return probe
  elseif overview.height ~= nil and type(overview.height) ~= "number" then
    probe.mapOverviewStatus = "INVALID"
    probe.semanticsReason = "MAP_OVERVIEW_HEIGHT_INVALID"
    return probe
  end
  for _, row in ipairs(overview.rows) do
    if type(row) ~= "string" then
      probe.mapOverviewStatus = "INVALID"
      probe.semanticsReason = "MAP_OVERVIEW_ROWS_INVALID"
      return probe
    end
  end
  probe.mapOverviewStatus = "OK"
  mapId = mapId or overview.mapId
  probe.mapId = mapId
  runtimeIdentity = runtimeIdentity or EngineTopology.identityFromMod(mod, mapId)
  local cacheIdentity = tostring(runtimeIdentity) .. ":"
    .. tostring(overview.width) .. ":" .. tostring(overview.height) .. ":"
    .. table.concat(overview.rows, "\n")
  if allowCache and not overrides and cache and cache.mapId == mapId
    and cache.identity == cacheIdentity then
    probe.semanticsStatus = "READY"
    probe.semanticsReason = "CACHE_HIT"
    probe.semantics = cache.semantics
    return probe
  end
  local configured = not overrides and Config.worldSemantics
    and Config.worldSemantics[mapId]
    or nil
  local topology = topologyProbe.topology
  local semantics = WorldSemantics.fromOverview(overview, overrides or configured, topology)
  if semantics and mapId and not overrides then
    if allowCache then
      semanticsGeneration = semanticsGeneration + 1
      semantics.generation = semanticsGeneration
      cache = {
        mapId = mapId,
        runtimeIdentity = runtimeIdentity,
        identity = cacheIdentity,
        semantics = semantics
      }
    end
  end
  if semantics then
    probe.semanticsStatus = "READY"
    probe.semanticsReason = "READY"
    probe.semantics = semantics
  else
    probe.semanticsReason = "SEMANTICS_BUILD_FAILED"
  end
  return probe
end

function WorldSemantics.probeFromMod(mod, mapId, overrides)
  return probeFromMod(mod, mapId, overrides, false)
end

function WorldSemantics.fromMod(mod, mapId, overrides)
  local probe = probeFromMod(mod, mapId, overrides, true)
  lastProductionProbe = probe
  return probe.semantics
end

function WorldSemantics.getLastProductionProbe(mapId)
  if mapId ~= nil and lastProductionProbe and lastProductionProbe.mapId ~= mapId then
    return nil
  end
  return lastProductionProbe
end

function WorldSemantics.isInside(semantics, x, y)
  return semantics ~= nil
    and x >= 0 and y >= 0
    and x < (semantics.width or 0)
    and y < (semantics.height or 0)
end

function WorldSemantics.cellAt(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then
    return { kind = "SIMULATION_BOUNDARY", walkable = false, validLanding = false }
  end
  local override = semantics.cellOverrides and semantics.cellOverrides[key(x, y)]
  if override then
    if type(override) == "string" then
      return { kind = override, walkable = override == "GROUND", validLanding = override == "GROUND" }
    end
    return copyRecord(override)
  end
  local row = semantics.rows[y + 1] or ""
  return baseCell(row:sub(x + 1, x + 1))
end

function WorldSemantics.edgeAt(semantics, fromX, fromY, toX, toY)
  local override = semantics and semantics.edgeOverrides
    and semantics.edgeOverrides[edgeKey(fromX, fromY, toX, toY)]
  return override and copyRecord(override) or nil
end

function WorldSemantics.transitionAt(semantics, x, y)
  local transition = semantics and semantics.transitions
    and semantics.transitions[key(x, y)]
  return transition and copyRecord(transition) or nil
end

function WorldSemantics.overviewCellAt(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then
    return nil
  end
  local row = semantics.rows[y + 1] or ""
  return row:sub(x + 1, x + 1)
end

function WorldSemantics.isConnectionSource(semantics, x, y)
  return semantics ~= nil
    and semantics.connectionSourceCells ~= nil
    and semantics.connectionSourceCells[key(x, y)] == true
end

function WorldSemantics.isUsableConnectionSource(semantics, x, y)
  return semantics ~= nil
    and semantics.usableConnectionSourceCells ~= nil
    and semantics.usableConnectionSourceCells[key(x, y)] == true
end

function WorldSemantics.spawnSemanticsAt(semantics, x, y, entity)
  if not WorldSemantics.isInside(semantics, x, y) then
    return {
      spawnClass = "UNKNOWN",
      spawnAllowed = false,
      spawnRestrictionReason = "OUT_OF_BOUNDS"
    }
  end
  local cell = WorldSemantics.cellAt(semantics, x, y)
  if cell.spawnAllowed ~= nil or cell.spawnClass ~= nil then
    local allowed = cell.spawnAllowed
    if allowed == nil then allowed = cell.spawnClass == "HABITAT" end
    return {
      spawnClass = cell.spawnClass or (allowed and "HABITAT" or "NON_HABITAT"),
      spawnAllowed = allowed == true,
      spawnRestrictionReason = cell.spawnRestrictionReason
        or (allowed and "NONE" or "NON_HABITAT")
    }
  end
  if WorldSemantics.isUsableConnectionSource(semantics, x, y) then
    local transition = WorldSemantics.transitionAt(semantics, x, y)
    return {
      spawnClass = "TRANSITION",
      spawnAllowed = false,
      spawnRestrictionReason = transition and transition.kind == "OVERWORLD_EXIT"
        and "OVERWORLD_CONNECTION_SOURCE" or "MAP_CONNECTION_SOURCE"
    }
  end
  if WorldSemantics.isLandingAllowed(semantics, x, y, "WALK") then
    return {
      spawnClass = "HABITAT",
      spawnAllowed = true,
      spawnRestrictionReason = "NONE"
    }
  end
  return {
    spawnClass = "NON_HABITAT",
    spawnAllowed = false,
    spawnRestrictionReason = "INVALID_LANDING"
  }
end

function WorldSemantics.isSpawnAllowed(semantics, x, y, entity)
  return WorldSemantics.spawnSemanticsAt(semantics, x, y, entity).spawnAllowed == true
end

function WorldSemantics.isLandingAllowed(semantics, x, y, mode)
  if not semantics then
    return false
  end
  local cell = WorldSemantics.cellAt(semantics, x, y)
  if cell.landingModes and cell.landingModes[mode] ~= nil then
    return cell.landingModes[mode] == true
  end
  if mode == "WALK" then
    return cell.walkable == true
  elseif mode == "SWIM" then
    return cell.swimmable == true
  end
  return cell.validLanding == true
end

function WorldSemantics.isEdgeAllowed(semantics, fromX, fromY, toX, toY, mode)
  if not semantics then
    return false
  end
  local edge = WorldSemantics.edgeAt(semantics, fromX, fromY, toX, toY)
  if not edge then
    return mode == "WALK" or mode == "SWIM"
  end
  if edge[mode] ~= nil then
    return edge[mode] == true
  end
  return mode == "WALK" or mode == "SWIM"
end

function WorldSemantics.blocksLineOfSight(semantics, x, y)
  if not semantics then
    return false
  end
  return WorldSemantics.cellAt(semantics, x, y).blocksLineOfSight == true
end

function WorldSemantics.clearCache(mapId)
  if not mapId or (cache and cache.mapId == mapId) then
    cache = nil
  end
end

function WorldSemantics.isOutdoorMap(semantics)
  return semantics ~= nil
    and semantics.environmentClass == "OUTDOOR"
    and semantics.mapKind ~= "CAVE"
    and semantics.mapKind ~= "INTERIOR"
end

function WorldSemantics.cellKey(x, y)
  return key(x, y)
end

function WorldSemantics.edgeKey(fromX, fromY, toX, toY)
  return edgeKey(fromX, fromY, toX, toY)
end

return require("src.world.world_semantics_v2")