local Config = require("src.core.config")
local EngineTopology = require("src.world.engine_topology")
local SemanticAnnotations = require("src.world.semantic_annotations")
local SemanticSource = require("src.world.semantic_source")

local WorldSemantics = {}

local DIRECTIONS = {
  UP = { dx = 0, dy = -1, topology = "north" },
  DOWN = { dx = 0, dy = 1, topology = "south" },
  LEFT = { dx = -1, dy = 0, topology = "west" },
  RIGHT = { dx = 1, dy = 0, topology = "east" }
}

local cache = nil
local generation = 0
local lastProductionProbe = nil

local function cellKey(x, y)
  return tostring(x) .. ":" .. tostring(y)
end

local function edgeKey(fromX, fromY, toX, toY)
  return cellKey(fromX, fromY) .. ">" .. cellKey(toX, toY)
end

local function tilePairKey(fromTile, toTile)
  return tostring(fromTile) .. ">" .. tostring(toTile)
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = copy(item) end
  return result
end

local function transientState(semantics)
  semantics.cellCache = semantics.cellCache or {}
  semantics.edgeCache = semantics.edgeCache or {}
  semantics.metrics = semantics.metrics or {}
  local metrics = semantics.metrics
  metrics.cellQueries = metrics.cellQueries or 0
  metrics.cellCacheHits = metrics.cellCacheHits or 0
  metrics.cellClassifications = metrics.cellClassifications or 0
  metrics.edgeQueries = metrics.edgeQueries or 0
  metrics.edgeCacheHits = metrics.edgeCacheHits or 0
  metrics.edgeClassifications = metrics.edgeClassifications or 0
  metrics.neighborhoodScans = metrics.neighborhoodScans or 0
  metrics.neighborhoodCells = metrics.neighborhoodCells or 0
  return metrics
end

local function merge(base, overlay)
  local result = copy(base or {})
  for key, value in pairs(overlay or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = merge(result[key], value)
    else
      result[key] = copy(value)
    end
  end
  return result
end

local function mapAnnotations(mapId, overrides)
  local authored = SemanticAnnotations.maps[mapId] or {}
  local configured = Config.worldSemantics and Config.worldSemantics[mapId] or {}
  return merge(merge(authored, configured), overrides)
end

local function tilesetAnnotations(tilesetId, overrides)
  local authored = SemanticAnnotations.tilesets[tilesetId] or {}
  local supplied = overrides and overrides.tilesets
    and overrides.tilesets[tilesetId] or {}
  return merge(authored, supplied)
end

local function configuredMapKind(mapId)
  local annotation = mapAnnotations(mapId)
  return annotation.mapKind or "OTHER"
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
    for _, cell in ipairs(connection.usableSourceCells or connection.sourceCells or {}) do
      transitions[cellKey(cell.cellX, cell.cellY)] = {
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
    transitions[cellKey(warp.cellX, warp.cellY)] = {
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
  local sources, usable = {}, {}
  for _, connection in ipairs(topology and topology.connections or {}) do
    for _, cell in ipairs(connection.sourceCells or {}) do
      sources[cellKey(cell.cellX, cell.cellY)] = true
    end
    for _, cell in ipairs(connection.usableSourceCells or {}) do
      usable[cellKey(cell.cellX, cell.cellY)] = true
    end
  end
  return sources, usable
end

local function build(snapshot, overrides, topology)
  if not snapshot or type(snapshot.rows) ~= "table" then return nil end
  local annotations = mapAnnotations(snapshot.mapId, overrides)
  local mapKind = annotations.mapKind or "OTHER"
  local environmentClass = annotations.environmentClass
    or topology and topology.environmentClass or "UNKNOWN"
  if not annotations.environmentClass
    and (mapKind == "CAVE" or mapKind == "INTERIOR") then
    environmentClass = "NON_OUTDOOR"
  end
  local transitions = derivedTransitions(environmentClass, topology)
  for key, transition in pairs(annotations.transitions or {}) do
    transitions[key] = copy(transition)
  end
  local sources, usable = connectionCellSets(topology)
  return {
    mapId = snapshot.mapId,
    mapKind = mapKind,
    environmentClass = environmentClass,
    width = snapshot.width or #(snapshot.rows[1] or ""),
    height = snapshot.height or #snapshot.rows,
    rows = snapshot.rows,
    snapshot = snapshot,
    mapAnnotations = annotations,
    tilesetAnnotations = tilesetAnnotations(snapshot.tilesetId, overrides),
    cellOverrides = annotations.cells or {},
    edgeOverrides = annotations.edges or {},
    transitions = transitions,
    connectionSourceCells = sources,
    usableConnectionSourceCells = usable,
    connections = topology and topology.connections or {},
    warps = topology and topology.warps or {},
    topology = topology,
    cellCache = {},
    edgeCache = {},
    metrics = {
      cellQueries = 0, cellCacheHits = 0, cellClassifications = 0,
      edgeQueries = 0, edgeCacheHits = 0, edgeClassifications = 0,
      neighborhoodScans = 0, neighborhoodCells = 0
    }
  }
end

function WorldSemantics.fromOverview(overview, overrides, topology)
  if not overview or type(overview.rows) ~= "table" then return nil end
  return build({
    mapId = overview.mapId,
    width = overview.width,
    height = overview.height,
    rows = overview.rows,
    markers = overview.markers or {},
    tilesetId = overview.tilesetId,
    mapDef = overview.mapDef,
    tileset = overview.tileset,
    ledges = overview.ledges or {},
    tilePairs = overview.tilePairs or { land = {}, water = {} },
    provenance = overview.provenance or { overview = "SYNTHETIC" }
  }, overrides, topology)
end

function WorldSemantics.fromSnapshot(snapshot, overrides, topology)
  return build(snapshot, overrides, topology)
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
    topologyProbe = topologyProbe,
    topologyStatus = topologyProbe.topologyStatus,
    topologyReason = topologyProbe.topologyReason,
    topologyMapId = topologyProbe.topologyMapId
  }
  if allowCache and not overrides and cache and cache.mapId == mapId
    and (runtimeIdentity == nil or cache.runtimeIdentity == runtimeIdentity) then
    probe.mapOverviewStatus = "NOT_PROBED_CACHE"
    probe.semanticsStatus = "READY"
    probe.semanticsReason = "CACHE_HIT"
    probe.semantics = cache.semantics
    return probe
  end
  local snapshot, reason, detail = SemanticSource.fromMod(mod, mapId)
  if not snapshot then
    probe.mapOverviewStatus = reason == "MAP_OVERVIEW_ERROR" and "ERROR"
      or reason == "MAP_OVERVIEW_NIL" and "NIL"
      or reason and reason:find("INVALID", 1, true) and "INVALID"
      or reason == "MAP_OVERVIEW_ROWS_MISSING" and "INVALID"
      or "UNAVAILABLE"
    probe.semanticsReason = reason
    if detail then probe.mapOverviewError = shortError(detail) end
    return probe
  end
  probe.mapOverviewStatus = "OK"
  probe.overviewMapId = snapshot.mapId
  probe.overviewWidth = snapshot.width
  probe.overviewHeight = snapshot.height
  probe.overviewRows = #snapshot.rows
  local semantics = build(snapshot, overrides, topologyProbe.topology)
  if not semantics then
    probe.semanticsReason = "SEMANTICS_BUILD_FAILED"
    return probe
  end
  if allowCache and not overrides then
    generation = generation + 1
    semantics.generation = generation
    cache = { mapId = mapId, runtimeIdentity = runtimeIdentity,
      semantics = semantics }
  end
  probe.semanticsStatus = "READY"
  probe.semanticsReason = "READY"
  probe.semantics = semantics
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
  if mapId and lastProductionProbe and lastProductionProbe.mapId ~= mapId then return nil end
  return lastProductionProbe
end

function WorldSemantics.isInside(semantics, x, y)
  return semantics ~= nil and x >= 0 and y >= 0
    and x < (semantics.width or 0) and y < (semantics.height or 0)
end

local function rawCell(semantics, x, y)
  local raw = SemanticSource.cell(semantics.snapshot, x, y)
  if raw then return raw end
  local row = semantics.rows[y + 1] or ""
  local char = row:sub(x + 1, x + 1)
  return {
    collisionClass = char,
    walkable = char == ".",
    water = char == "~",
    warp = char == "+",
    blocked = char == " ",
    grass = false
  }
end

local function baseCell(raw)
  if raw.grass then
    return { kind = "GROUND", terrain = "TALL_GRASS", walkable = true,
      validLanding = true, blocksLineOfSight = false, cover = "HIGH" }
  elseif raw.water then
    return { kind = "WATER", terrain = "WATER", walkable = false,
      swimmable = true, validLanding = false, blocksLineOfSight = false,
      cover = "NONE" }
  elseif raw.walkable then
    return { kind = "GROUND", terrain = "OPEN_GROUND", walkable = true,
      validLanding = true, blocksLineOfSight = false, cover = "NONE" }
  elseif raw.warp then
    return { kind = "MAP_TRANSITION", terrain = "UNKNOWN", walkable = false,
      validLanding = false, blocksLineOfSight = false, cover = "UNKNOWN" }
  end
  return { kind = "UNKNOWN_BARRIER", terrain = "UNKNOWN", walkable = false,
    validLanding = false, blocksLineOfSight = true, cover = "UNKNOWN" }
end

local function cellAnnotation(semantics, raw, x, y)
  local tileset = semantics.tilesetAnnotations or {}
  local result = {}
  if raw.blockId ~= nil and tileset.blocks then
    result = merge(result, tileset.blocks[raw.blockId])
  end
  if raw.tileId ~= nil and tileset.tiles then
    result = merge(result, tileset.tiles[raw.tileId])
  end
  local override = (semantics.cellOverrides or {})[cellKey(x, y)]
  if type(override) == "string" then override = { terrain = override } end
  return merge(result, override)
end

function WorldSemantics.describeCell(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then
    return { mapId = semantics and semantics.mapId, x = x, y = y,
      kind = "SIMULATION_BOUNDARY", terrain = "UNKNOWN", walkable = false,
      validLanding = false, contextTags = { "MAP_BOUNDARY" } }
  end
  local metrics = transientState(semantics)
  metrics.cellQueries = metrics.cellQueries + 1
  local cacheKey = cellKey(x, y)
  local cached = semantics.cellCache[cacheKey]
  if cached then
    metrics.cellCacheHits = metrics.cellCacheHits + 1
    return copy(cached)
  end
  metrics.cellClassifications = metrics.cellClassifications + 1
  local raw = rawCell(semantics, x, y)
  local described = merge(baseCell(raw), cellAnnotation(semantics, raw, x, y))
  described.mapId, described.x, described.y = semantics.mapId, x, y
  described.water = raw.water == true
  described.grass = raw.grass == true
  described.walkableByPlayer = raw.walkableByPlayer ~= nil
    and raw.walkableByPlayer or raw.walkable == true
  described.contextTags = copy(described.contextTags or {})
  described.raw = {
    collisionClass = raw.collisionClass,
    tilesetId = raw.tilesetId,
    blockId = raw.blockId,
    tileId = raw.tileId,
    source = copy(semantics.snapshot and semantics.snapshot.provenance)
  }
  semantics.cellCache[cacheKey] = described
  return copy(described)
end

function WorldSemantics.cellAt(semantics, x, y)
  return WorldSemantics.describeCell(semantics, x, y)
end

local function directionFor(fromX, fromY, toX, toY)
  local dx, dy = toX - fromX, toY - fromY
  for name, direction in pairs(DIRECTIONS) do
    if direction.dx == dx and direction.dy == dy then return name, direction end
  end
  return nil, nil
end

local function listContains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

local function edgeEvidence(semantics, source, destination, direction)
  local rawSource, rawDestination = source.raw or {}, destination.raw or {}
  local snapshot = semantics.snapshot or {}
  for _, ledge in ipairs(snapshot.ledges or {}) do
    if (ledge.tileset or "OVERWORLD") == rawSource.tilesetId
      and ledge.facing == direction:lower() and ledge.input == direction:lower()
      and ledge.standingTile == rawSource.tileId
      and ledge.ledgeTile == rawDestination.tileId then
      return "LEDGE", "FIELD_LEDGE_ROW"
    end
  end
  for _, pair in ipairs(snapshot.tilePairs and snapshot.tilePairs.land or {}) do
    if pair.tileset == rawSource.tilesetId
      and ((pair.a == rawSource.tileId and pair.b == rawDestination.tileId)
        or (pair.b == rawSource.tileId and pair.a == rawDestination.tileId)) then
      return "ELEVATION_RESTRICTION", "FIELD_TILE_PAIR"
    end
  end
  return nil, nil
end

local function authoredEdge(semantics, source, destination, exactKey)
  local mapEdge = (semantics.edgeOverrides or {})[exactKey]
  if mapEdge then return copy(mapEdge), "MAP_EDGE" end
  local edges = semantics.tilesetAnnotations and semantics.tilesetAnnotations.edges
  local pair = edges and edges[tilePairKey(source.raw.tileId, destination.raw.tileId)]
  if pair then return copy(pair), "TILESET_TILE_PAIR" end
  return nil, nil
end

local function transitionForEdge(semantics, x, y, direction)
  local transition = (semantics.transitions or {})[cellKey(x, y)]
  if transition and (transition.topologyKind == "WARP"
    or transition.direction == direction.topology) then return transition end
  return nil
end

function WorldSemantics.describeEdge(semantics, x, y, directionName)
  local direction = DIRECTIONS[tostring(directionName):upper()]
  if not semantics or not direction then return nil end
  local metrics = transientState(semantics)
  metrics.edgeQueries = metrics.edgeQueries + 1
  local toX, toY = x + direction.dx, y + direction.dy
  local cacheKey = edgeKey(x, y, toX, toY)
  local cached = semantics.edgeCache[cacheKey]
  if cached then
    metrics.edgeCacheHits = metrics.edgeCacheHits + 1
    return copy(cached)
  end
  metrics.edgeClassifications = metrics.edgeClassifications + 1
  local source = WorldSemantics.describeCell(semantics, x, y)
  local destination = WorldSemantics.describeCell(semantics, toX, toY)
  local result = {
    mapId = semantics.mapId,
    direction = directionName:upper(),
    source = { cellX = x, cellY = y },
    destination = { cellX = toX, cellY = toY },
    sourceSemantic = source.terrain,
    destinationSemantic = destination.terrain,
    topologyKind = "SAME_MAP",
    boundaryKind = "NONE",
    barrierKind = "OPEN",
    rawWalkability = source.walkable == true and destination.walkable == true,
    traversal = { executable = { WALK = false, SWIM = false }, future = {} }
  }
  if not WorldSemantics.isInside(semantics, toX, toY) then
    local transition = transitionForEdge(semantics, x, y, direction)
    result.topologyKind = transition and "MAP_CONNECTION" or "HARD_BOUNDARY"
    result.boundaryKind = transition and "MAP_CONNECTION" or "MAP_BOUNDARY"
    result.barrierKind = transition and "OPEN" or "MAP_BOUNDARY"
    result.transition = copy(transition)
  else
    local authored, sourceKind = authoredEdge(semantics, source, destination, cacheKey)
    local evidence, evidenceSource = edgeEvidence(
      semantics, source, destination, result.direction)
    if authored then
      result = merge(result, authored)
      result.classificationSource = sourceKind
    elseif evidence == "LEDGE" then
      result.barrierKind = "LEDGE"
      result.classificationSource = evidenceSource
      result.traversal.future.JUMP = "POSSIBLE_WITH_CAPABILITY"
    elseif evidence then
      result.barrierKind = evidence
      result.classificationSource = evidenceSource
      result.traversal.future.CLIMB = "POSSIBLE_WITH_CAPABILITY"
    elseif source.water ~= destination.water then
      result.barrierKind = "WATER_BOUNDARY"
      result.classificationSource = "NEIGHBORHOOD"
      result.traversal.future.SWIM = "POSSIBLE_WITH_CAPABILITY"
    elseif not result.rawWalkability then
      result.barrierKind = "UNKNOWN_BARRIER"
      result.classificationSource = "RAW_COLLISION"
    else
      result.classificationSource = "RAW_COLLISION"
    end
    result.traversal.executable.WALK = result.rawWalkability
      and result.barrierKind == "OPEN"
    result.traversal.executable.SWIM = source.water and destination.water
    if result.barrierKind == "FENCE" then
      result.traversal.future.SQUEEZE = "POSSIBLE_WITH_CAPABILITY"
      result.traversal.future.FLY = "POSSIBLE_WITH_CAPABILITY"
    elseif result.barrierKind == "CLIFF"
      or result.barrierKind == "ELEVATION_RESTRICTION" then
      result.traversal.future.CLIMB = "POSSIBLE_WITH_CAPABILITY"
      result.traversal.future.FLY = "POSSIBLE_WITH_CAPABILITY"
    elseif result.barrierKind == "WATER_BOUNDARY" then
      result.traversal.future.SWIM = "POSSIBLE_WITH_CAPABILITY"
      result.traversal.future.FLY = "POSSIBLE_WITH_CAPABILITY"
    end
  end
  semantics.edgeCache[cacheKey] = result
  return copy(result)
end

function WorldSemantics.edgeAt(semantics, fromX, fromY, toX, toY)
  local direction = directionFor(fromX, fromY, toX, toY)
  local described = direction and WorldSemantics.describeEdge(
    semantics, fromX, fromY, direction) or nil
  if not described then return nil end
  local legacy = copy((semantics.edgeOverrides or {})[
    edgeKey(fromX, fromY, toX, toY)] or {})
  legacy.kind = legacy.kind or described.barrierKind
  legacy.barrierKind = described.barrierKind
  if legacy.WALK == nil then
    legacy.WALK = described.traversal.executable.WALK
  end
  if legacy.SWIM == nil then
    legacy.SWIM = described.traversal.executable.SWIM
  end
  return legacy
end

function WorldSemantics.transitionAt(semantics, x, y)
  local transition = semantics and (semantics.transitions or {})[cellKey(x, y)]
  return transition and copy(transition) or nil
end

function WorldSemantics.overviewCellAt(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then return nil end
  return (semantics.rows[y + 1] or ""):sub(x + 1, x + 1)
end

function WorldSemantics.isConnectionSource(semantics, x, y)
  return semantics ~= nil and (semantics.connectionSourceCells or {})[cellKey(x, y)] == true
end

function WorldSemantics.isUsableConnectionSource(semantics, x, y)
  return semantics ~= nil
    and (semantics.usableConnectionSourceCells or {})[cellKey(x, y)] == true
end

function WorldSemantics.spawnSemanticsAt(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then
    return { spawnClass = "UNKNOWN", spawnAllowed = false,
      spawnRestrictionReason = "OUT_OF_BOUNDS" }
  end
  local cell = WorldSemantics.describeCell(semantics, x, y)
  if cell.spawnAllowed ~= nil or cell.spawnClass ~= nil then
    local allowed = cell.spawnAllowed
    if allowed == nil then allowed = cell.spawnClass == "HABITAT" end
    return { spawnClass = cell.spawnClass or (allowed and "HABITAT" or "NON_HABITAT"),
      spawnAllowed = allowed == true,
      spawnRestrictionReason = cell.spawnRestrictionReason
        or (allowed and "NONE" or "NON_HABITAT") }
  end
  if WorldSemantics.isUsableConnectionSource(semantics, x, y) then
    local transition = WorldSemantics.transitionAt(semantics, x, y)
    return { spawnClass = "TRANSITION", spawnAllowed = false,
      spawnRestrictionReason = transition and transition.kind == "OVERWORLD_EXIT"
        and "OVERWORLD_CONNECTION_SOURCE" or "MAP_CONNECTION_SOURCE" }
  end
  if WorldSemantics.isLandingAllowed(semantics, x, y, "WALK") then
    return { spawnClass = "HABITAT", spawnAllowed = true,
      spawnRestrictionReason = "NONE" }
  end
  return { spawnClass = "NON_HABITAT", spawnAllowed = false,
    spawnRestrictionReason = "INVALID_LANDING" }
end

function WorldSemantics.isSpawnAllowed(semantics, x, y)
  return WorldSemantics.spawnSemanticsAt(semantics, x, y).spawnAllowed == true
end

function WorldSemantics.isLandingAllowed(semantics, x, y, mode)
  if not semantics then
    return false
  end
  local cell = WorldSemantics.describeCell(semantics, x, y)
  if cell.landingModes and cell.landingModes[mode] ~= nil then
    return cell.landingModes[mode] == true
  end
  if mode == "WALK" then return cell.walkable == true end
  if mode == "SWIM" then return cell.swimmable == true end
  return cell.validLanding == true
end

function WorldSemantics.isEdgeAllowed(semantics, fromX, fromY, toX, toY, mode)
  if not semantics then
    return false
  end
  local edge = WorldSemantics.edgeAt(semantics, fromX, fromY, toX, toY)
  return edge ~= nil and edge[mode] == true
end

function WorldSemantics.blocksLineOfSight(semantics, x, y)
  if not semantics then
    return false
  end
  return WorldSemantics.describeCell(semantics, x, y).blocksLineOfSight == true
end

local function addTag(cell, tag)
  if not listContains(cell.contextTags, tag) then
    cell.contextTags[#cell.contextTags + 1] = tag
  end
end

function WorldSemantics.describeContext(semantics, x, y)
  local cell = WorldSemantics.describeCell(semantics, x, y)
  if not WorldSemantics.isInside(semantics, x, y) then return cell end
  local grassNeighbors, waterNeighbors = 0, 0
  for _, direction in pairs(DIRECTIONS) do
    local neighbor = WorldSemantics.describeCell(
      semantics, x + direction.dx, y + direction.dy)
    if neighbor.grass then grassNeighbors = grassNeighbors + 1 end
    if neighbor.water then waterNeighbors = waterNeighbors + 1 end
  end
  if cell.grass then
    cell.grassRelation = grassNeighbors == 4 and "INTERIOR" or "EDGE"
    if cell.grassRelation == "EDGE" then addTag(cell, "GRASS_EDGE") end
  elseif grassNeighbors > 0 then
    cell.grassRelation = "ADJACENT"
    addTag(cell, "GRASS_ADJACENT")
  else
    cell.grassRelation = "NONE"
  end
  if not cell.water and waterNeighbors > 0 then addTag(cell, "WATER_ADJACENT") end
  cell.waterNeighborCount = waterNeighbors
  cell.grassNeighborCount = grassNeighbors
  table.sort(cell.contextTags)
  return cell
end

local function featureMatches(cell, semantic)
  if cell.terrain == semantic or cell.cover == semantic then return true end
  return listContains(cell.contextTags, semantic)
end

function WorldSemantics.scanNeighborhood(semantics, x, y, radius)
  radius = math.max(0, math.floor(radius or 0))
  local metrics = transientState(semantics)
  metrics.neighborhoodScans = metrics.neighborhoodScans + 1
  local result = { mapId = semantics.mapId, center = { cellX = x, cellY = y },
    radius = radius, counts = {}, locations = {}, cellsVisited = 0 }
  for scanY = y - radius, y + radius do
    for scanX = x - radius, x + radius do
      if WorldSemantics.isInside(semantics, scanX, scanY)
        and math.max(math.abs(scanX - x), math.abs(scanY - y)) <= radius then
        local cell = WorldSemantics.describeContext(semantics, scanX, scanY)
        result.cellsVisited = result.cellsVisited + 1
        result.counts[cell.terrain] = (result.counts[cell.terrain] or 0) + 1
        result.locations[#result.locations + 1] = cell
      end
    end
  end
  metrics.neighborhoodCells = metrics.neighborhoodCells + result.cellsVisited
  return result
end

function WorldSemantics.findNearbyFeature(semantics, actorCell, semantic, radius)
  local scan = WorldSemantics.scanNeighborhood(
    semantics, actorCell.cellX, actorCell.cellY, radius)
  local results = {}
  for _, cell in ipairs(scan.locations) do
    if featureMatches(cell, semantic) then
      cell.distance = math.abs(cell.x - actorCell.cellX)
        + math.abs(cell.y - actorCell.cellY)
      results[#results + 1] = cell
    end
  end
  table.sort(results, function(left, right)
    if left.distance ~= right.distance then return left.distance < right.distance end
    if left.y ~= right.y then return left.y < right.y end
    return left.x < right.x
  end)
  return results
end

function WorldSemantics.metricsSnapshot(semantics)
  local result = copy(semantics and semantics.metrics or {})
  local total = (result.cellQueries or 0) + (result.edgeQueries or 0)
  local hits = (result.cellCacheHits or 0) + (result.edgeCacheHits or 0)
  result.cacheHitRate = total > 0 and hits / total or 0
  return result
end

function WorldSemantics.inspect(semantics, x, y)
  local cell = WorldSemantics.describeContext(semantics, x, y)
  local lines = {
    "CELL",
    "map=" .. tostring(semantics.mapId),
    "cell=" .. tostring(x) .. "," .. tostring(y),
    "tileset=" .. tostring(cell.raw and cell.raw.tilesetId),
    "block=" .. tostring(cell.raw and cell.raw.blockId),
    "tile=" .. tostring(cell.raw and cell.raw.tileId),
    "terrain=" .. tostring(cell.terrain),
    "cover=" .. tostring(cell.cover),
    "water=" .. tostring(cell.water),
    "grass=" .. tostring(cell.grass),
    "EDGES"
  }
  for _, direction in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
    local edge = WorldSemantics.describeEdge(semantics, x, y, direction)
    lines[#lines + 1] = direction .. "=" .. tostring(edge and edge.barrierKind)
  end
  return table.concat(lines, "\n")
end

function WorldSemantics.clearCache(mapId)
  if not mapId or cache and cache.mapId == mapId then cache = nil end
end

function WorldSemantics.isOutdoorMap(semantics)
  return semantics ~= nil and semantics.environmentClass == "OUTDOOR"
    and semantics.mapKind ~= "CAVE" and semantics.mapKind ~= "INTERIOR"
end

WorldSemantics.cellKey = cellKey
WorldSemantics.edgeKey = edgeKey
WorldSemantics.tilePairKey = tilePairKey

return WorldSemantics