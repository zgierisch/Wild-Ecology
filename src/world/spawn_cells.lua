local Config = require("src.core.config")
local WalkableCells = require("src.world.walkable_cells")
local WorldSemantics = require("src.world.world_semantics")
local NavigationPlanner = require("src.navigation.navigation_planner")
local PlayableComponent = require("src.world.playable_component")

local SpawnCells = {}
local candidateAnalysisRuns = 0

function SpawnCells.getCandidateAnalysisRunCount()
  return candidateAnalysisRuns
end

-- See src/entities/entity.lua's seededUnitInterval comment: the game
-- runtime is LuaJIT, so no bitwise operators and doubles-only precision.
-- Same portable modular-multiplication mix used throughout this codebase.
local MIX_MODULUS = 67108864 -- 2^26

local function seededUnit(seed, salt)
  local reduced = math.abs(math.floor(seed or 0)) % MIX_MODULUS
  local combined = (reduced * 40503199 + (salt or 0) * 40503) % MIX_MODULUS
  local mixed = (combined * 26146329 + 12345) % MIX_MODULUS
  return mixed / (MIX_MODULUS - 1)
end

local function routeSpawnConfig()
  local phase3 = Config.phase3 or {}
  return phase3.routeSpawnCells or {}
end

local function keyForCell(cell)
  return tostring(cell.x) .. ":" .. tostring(cell.y)
end

-- Picks a cell not already in occupiedKeys from `candidates`, starting at a
-- hashed index (a real scatter across the whole list, not a small
-- contiguous offset -- with a large candidate list a plain seed%count
-- offset barely moves for small seeds, clustering picks near each other).
local function pickFromCandidates(candidates, occupiedKeys, seed, viable)
  local count = #candidates
  if count == 0 then
    return nil
  end

  local startIndex = 1
  if seed ~= nil then
    startIndex = math.floor(seededUnit(seed, 71) * count) + 1
  end

  occupiedKeys = occupiedKeys or {}
  for step = 0, count - 1 do
    local candidate = candidates[((startIndex - 1 + step) % count) + 1]
    local cellKey = keyForCell(candidate)
    if not occupiedKeys[cellKey] and (not viable or viable(candidate)) then
      return { x = candidate.x, y = candidate.y }
    end
  end

  if not viable then
    local fallback = candidates[startIndex]
    return { x = fallback.x, y = fallback.y }
  end
  return nil
end

function SpawnCells.analyzeCandidates(mod, mapId, entity, semantics)
  candidateAnalysisRuns = candidateAnalysisRuns + 1
  semantics = semantics or WorldSemantics.fromMod(mod, mapId)
  local static = WalkableCells.analyzeSpawnableForMap(mod, mapId, semantics)
  if not static then
    return nil
  end
  local finalCandidates = {}
  local connectivityFailureSamples = {}
  local connectivityAccepted = 0
  local connectivityRejected = 0
  local outsidePlayableRejected = 0
  local outsidePlayableSamples = {}
  local playable = PlayableComponent.inspect(mod, mapId, semantics)
  for _, candidate in ipairs(static.spawnableCells) do
    local canonical = { cellX = candidate.x, cellY = candidate.y }
    if not PlayableComponent.contains(playable, candidate.x, candidate.y) then
      outsidePlayableRejected = outsidePlayableRejected + 1
      if #outsidePlayableSamples < 3 then
        outsidePlayableSamples[#outsidePlayableSamples + 1] = candidate
      end
    elseif not WorldSemantics.isOutdoorMap(semantics) or playable.exitConnected then
      finalCandidates[#finalCandidates + 1] = candidate
      connectivityAccepted = connectivityAccepted + 1
    else
      connectivityRejected = connectivityRejected + 1
      if #connectivityFailureSamples < 3 then
        connectivityFailureSamples[#connectivityFailureSamples + 1] = {
          x = candidate.x,
          y = candidate.y,
          reason = "NO_REACHABLE_OVERWORLD_EXIT"
        }
      end
    end
  end
  local stockConnectionCount = #(semantics.connections or {})
  local resolvedConnectionCount = 0
  local usableOverworldExitCount = 0
  local connectionSummaries = {}
  for _, connection in ipairs(semantics.connections or {}) do
    if connection.resolved == true then
      resolvedConnectionCount = resolvedConnectionCount + 1
    end
    if WorldSemantics.isOutdoorMap(semantics) then
      usableOverworldExitCount = usableOverworldExitCount + #(connection.usableSourceCells or {})
    end
    connectionSummaries[#connectionSummaries + 1] = {
      direction = connection.direction,
      destinationMapId = connection.destinationMapId,
      resolved = connection.resolved == true,
      resolutionReason = connection.resolutionReason or (connection.resolved and "READY" or "UNRESOLVED"),
      usableSourceCount = #(connection.usableSourceCells or {})
    }
  end
  local semanticsStatus = semantics.topology == nil and "UNAVAILABLE"
    or (resolvedConnectionCount < stockConnectionCount and "TOPOLOGY_UNRESOLVED" or "READY")
  local candidateStatus = "READY"
  if static.rawWalkable == 0 then
    candidateStatus = "NO_RAW_WALKABLE"
  elseif static.spawnSemanticAllowed == 0 then
    candidateStatus = "NO_SPAWNABLE_CELLS"
  elseif playable.status ~= "READY" then
    candidateStatus = "PLAYABLE_COMPONENT_UNAVAILABLE"
  elseif WorldSemantics.isOutdoorMap(semantics) and usableOverworldExitCount == 0 then
    candidateStatus = "NO_USABLE_EXIT"
  elseif connectivityAccepted == 0 then
    candidateStatus = "NO_CONNECTED_CANDIDATES"
  end
  return {
    mapId = static.mapId,
    semantics = semantics,
    environmentClass = semantics.environmentClass,
    width = semantics.width,
    height = semantics.height,
    rawWalkable = static.rawWalkable,
    landingValid = static.landingValid,
    landingRejected = static.landingRejected,
    spawnSemanticAllowed = static.spawnSemanticAllowed,
    spawnSemanticRejected = static.spawnSemanticRejected,
    connectionSourceRejected = static.connectionSourceRejected,
    connectivityAccepted = connectivityAccepted,
    connectivityRejected = connectivityRejected,
    spawnRejectedOutsidePlayableComponent = outsidePlayableRejected,
    outsidePlayableSamples = outsidePlayableSamples,
    rawPlayerCell = playable.rawPlayerCell,
    playerCell = playable.playerCell,
    componentSeedCell = playable.componentSeedCell,
    componentSeedSource = playable.componentSeedSource,
    componentSeedDirection = playable.componentSeedDirection,
    playableComponentReason = playable.reason,
    playableComponentId = playable.activeComponentId,
    playableComponentStatus = playable.status,
    playableComponentCells = playable.playableCells,
    walkComponentCount = playable.componentCount,
    exitConnectedComponentCount = playable.exitConnectedComponentCount,
    playableComponentBuildNumber = playable.buildNumber,
    finalCandidates = finalCandidates,
    connectivityFailureSamples = connectivityFailureSamples,
    connectionSummaries = connectionSummaries,
    finalCandidateCount = #finalCandidates,
    stockConnectionCount = stockConnectionCount,
    resolvedConnectionCount = resolvedConnectionCount,
    overworldExitCount = WorldSemantics.isOutdoorMap(semantics) and stockConnectionCount or 0,
    usableOverworldExitCount = usableOverworldExitCount,
    semanticsStatus = semanticsStatus,
    candidateStatus = candidateStatus,
    candidateAnalysisRuns = candidateAnalysisRuns,
    semanticsGeneration = semantics.generation,
    result = #finalCandidates > 0 and "READY" or "NO_SPAWN_CANDIDATES"
  }
end

function SpawnCells.formatCandidateAnalysis(analysis)
  if not analysis then
    return "SpawnCandidates result=UNAVAILABLE"
  end
  return string.format(
    "SpawnCandidates map=%s environmentClass=%s width=%s height=%s rawWalkable=%s landingValid=%s landingRejected=%s spawnSemanticAllowed=%s spawnSemanticRejected=%s connectionSourceRejected=%s rawPlayerCell=%s componentSeedCell=%s componentSeedSource=%s componentSeedDirection=%s componentSeedReason=%s playableComponentStatus=%s playableComponentCells=%s walkComponentCount=%s spawnRejectedOutsidePlayableComponent=%s connectivityAccepted=%s connectivityRejected=%s finalCandidates=%s stockConnectionCount=%s resolvedConnectionCount=%s overworldExitCount=%s usableOverworldExitCount=%s semanticsIdentity=%s result=%s",
    tostring(analysis.mapId), tostring(analysis.environmentClass),
    tostring(analysis.width), tostring(analysis.height),
    tostring(analysis.rawWalkable), tostring(analysis.landingValid),
    tostring(analysis.landingRejected), tostring(analysis.spawnSemanticAllowed),
    tostring(analysis.spawnSemanticRejected), tostring(analysis.connectionSourceRejected),
    analysis.rawPlayerCell and tostring(analysis.rawPlayerCell.cellX) .. "," .. tostring(analysis.rawPlayerCell.cellY) or "N/A",
    analysis.componentSeedCell and tostring(analysis.componentSeedCell.cellX) .. "," .. tostring(analysis.componentSeedCell.cellY) or "N/A",
    tostring(analysis.componentSeedSource), tostring(analysis.componentSeedDirection),
    tostring(analysis.playableComponentReason),
    tostring(analysis.playableComponentStatus), tostring(analysis.playableComponentCells),
    tostring(analysis.walkComponentCount), tostring(analysis.spawnRejectedOutsidePlayableComponent),
    tostring(analysis.connectivityAccepted), tostring(analysis.connectivityRejected),
    tostring(analysis.finalCandidateCount), tostring(analysis.stockConnectionCount),
    tostring(analysis.resolvedConnectionCount), tostring(analysis.overworldExitCount),
    tostring(analysis.usableOverworldExitCount), tostring(analysis.semantics),
    tostring(analysis.result)
  )
end

-- `mod` is optional: when a live mod.world:mapOverview() is available (real
-- gameplay), spawn cells scatter across the map's REAL walkable cells
-- instead of the small hand-authored Config.phase3.routeSpawnCells box.
-- Falls back to the configured cell list when mod.world isn't available
-- (headless tests) or mapOverview reports nothing usable.
function SpawnCells.pickCell(mapId, zoneId, occupiedKeys, seed, mod, entity, productionAnalysis)
  local semantics = entity and WorldSemantics.fromMod(mod, mapId) or nil
  local analysis = productionAnalysis
    or (semantics and SpawnCells.analyzeCandidates(mod, mapId, entity, semantics) or nil)
  local viable = semantics and function(candidate)
    local canonical = {
      cellX = candidate.x,
      cellY = candidate.y
    }
    return WorldSemantics.isSpawnAllowed(semantics, canonical.cellX, canonical.cellY, entity)
      and NavigationPlanner.isSpawnViable(entity, semantics, canonical)
  end or nil
  local realCells = analysis and analysis.finalCandidates
    or WalkableCells.computeSpawnableForMap(mod, mapId, semantics)
  if realCells then
    local picked = pickFromCandidates(realCells, occupiedKeys, seed)
    if picked then
      return picked
    end
    if analysis then
      return nil
    end
  end

  local cellsByZone = routeSpawnConfig()
  local candidates = cellsByZone[zoneId or ""] or cellsByZone.default or {}
  if #candidates == 0 then
    return { x = 6, y = 6 }
  end

  return pickFromCandidates(candidates, occupiedKeys, seed, viable)
    or (not viable and { x = 6, y = 6 } or nil)
end

function SpawnCells.pickDefaultCell(mapId, occupiedKeys, seed, mod)
  return SpawnCells.pickCell(mapId, "default", occupiedKeys, seed, mod)
end

function SpawnCells.keyForCell(cell)
  return keyForCell(cell)
end

function SpawnCells.isViable(entity, semantics, cell)
  local canonical = SpawnCells.canonicalCell(cell)
  return canonical ~= nil
    and WorldSemantics.isSpawnAllowed(semantics, canonical.cellX, canonical.cellY, entity)
    and NavigationPlanner.isSpawnViable(entity, semantics, canonical)
end

function SpawnCells.canonicalCell(cell)
  if type(cell) ~= "table" then
    return nil
  end
  local x = cell.cellX
  local y = cell.cellY
  if x == nil then x = cell.x end
  if y == nil then y = cell.y end
  if x == nil or y == nil then
    return nil
  end
  return { cellX = x, cellY = y }
end

function SpawnCells.inspect(entity, semantics, cell, mod, mapId)
  local canonical = SpawnCells.canonicalCell(cell)
  local details = {
    canonicalCell = canonical,
    worldWidth = semantics and semantics.width or nil,
    worldHeight = semantics and semantics.height or nil,
    environmentClass = semantics and semantics.environmentClass or "UNKNOWN",
    spawnAllowed = nil,
    requiresOverworldExit = WorldSemantics.isOutdoorMap(semantics)
  }
  if not semantics then
    details.reason = "UNKNOWN"
    details.spawnClass = "UNKNOWN"
    details.spawnRestrictionReason = "UNKNOWN_SEMANTICS"
    return details
  end
  if not canonical then
    details.reason = "MISSING_POSITION"
    details.inBounds = false
    details.isLandingAllowed = false
    details.spawnClass = "UNKNOWN"
    details.spawnRestrictionReason = "MISSING_POSITION"
    details.spawnViability = false
    details.spawnAllowed = false
    return details
  end
  local x, y = canonical.cellX, canonical.cellY
  details.inBounds = WorldSemantics.isInside(semantics, x, y)
  details.overviewCell = WorldSemantics.overviewCellAt(semantics, x, y)
  details.semanticCellKind = WorldSemantics.cellAt(semantics, x, y).kind
  details.connectionSource = WorldSemantics.isConnectionSource(semantics, x, y)
  details.usableConnectionSource = WorldSemantics.isUsableConnectionSource(semantics, x, y)
  if not details.inBounds then
    details.reason = "OUT_OF_BOUNDS"
    details.isLandingAllowed = false
    details.spawnClass = "UNKNOWN"
    details.spawnRestrictionReason = "OUT_OF_BOUNDS"
    details.spawnViability = false
    details.spawnAllowed = false
    return details
  end
  details.isLandingAllowed = WorldSemantics.isLandingAllowed(semantics, x, y, "WALK")
  if not details.isLandingAllowed then
    details.reason = "INVALID_PERSISTED_CELL"
    details.spawnClass = "NON_HABITAT"
    details.spawnRestrictionReason = "INVALID_LANDING"
    details.spawnViability = false
    details.spawnAllowed = false
    return details
  end
  local spawnSemantics = WorldSemantics.spawnSemanticsAt(semantics, x, y, entity)
  details.spawnClass = spawnSemantics.spawnClass
  details.spawnAllowed = spawnSemantics.spawnAllowed
  details.spawnRestrictionReason = spawnSemantics.spawnRestrictionReason
  if not details.spawnAllowed then
    details.reason = "NON_SPAWNABLE_CELL"
    details.spawnViability = false
    return details
  end
  local playable = mod and PlayableComponent.inspect(mod, mapId or semantics.mapId, semantics) or nil
  if playable then
    details.rawPlayerCell = playable.rawPlayerCell
    details.playerCell = playable.playerCell
    details.componentSeedCell = playable.componentSeedCell
    details.componentSeedSource = playable.componentSeedSource
    details.componentSeedDirection = playable.componentSeedDirection
    details.playableComponentReason = playable.reason
    details.playableComponentId = playable.activeComponentId
    details.playableComponentStatus = playable.status
    details.playableComponentCells = playable.playableCells
    details.walkComponentCount = playable.componentCount
    details.exitConnectedComponentCount = playable.exitConnectedComponentCount
    details.insidePlayableComponent = PlayableComponent.contains(playable, x, y)
    if playable.status ~= "READY" then
      details.reason = "PLAYABLE_COMPONENT_UNAVAILABLE"
      details.spawnViability = false
      return details
    elseif not details.insidePlayableComponent then
      details.reason = "OUTSIDE_PLAYABLE_COMPONENT"
      details.spawnViability = false
      return details
    end
  end
  details.reachableOverworldExit = details.requiresOverworldExit
    and (playable and playable.exitConnected
      or NavigationPlanner.hasReachableOverworldExit(entity, semantics, canonical))
    or nil
  details.spawnViability = not details.requiresOverworldExit
    or details.reachableOverworldExit == true
  details.reason = details.spawnViability and "VALID" or "NO_TRAVERSABLE_EXIT"
  return details
end

function SpawnCells.assess(entity, semantics, cell, mod, mapId)
  local details = SpawnCells.inspect(entity, semantics, cell, mod, mapId)
  return details.reason, details
end

return SpawnCells
