local TraversalCapabilities = require("src.navigation.traversal_capabilities")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local BoundedSearch = require("src.navigation.bounded_search")
local NavigationEpisode = require("src.navigation.navigation_episode")
local WorldSemantics = require("src.world.world_semantics")

local FleeEscape = {}

local counters = {
  boundedFleePlannerCalls = 0,
  boundedFleeRouteObjectsCreated = 0,
  boundedFleePlannerCallsSuppressed = 0,
  boundedFleePlannerDirtyEvents = 0,
  dirtyByActorMovement = 0,
  dirtyByBlockerMovement = 0,
  dirtyByBlockerReplacement = 0,
  dirtyByClaimChange = 0,
  dirtyByThreatChange = 0,
  dirtyBySocialVector = 0,
  dirtyByTopologyChange = 0,
  dirtyByWatchdog = 0,
  socialVectorUpdatesObserved = 0,
  socialVectorUpdatesMaterial = 0,
  socialVectorUpdatesIgnoredAsEquivalent = 0
}

function FleeEscape.getCounters()
  local result = {}
  for key, value in pairs(counters) do result[key] = value end
  return result
end

function FleeEscape.resetCounters()
  for key in pairs(counters) do counters[key] = 0 end
end

function FleeEscape.recordSuppressedPlan()
  counters.boundedFleePlannerCallsSuppressed
    = counters.boundedFleePlannerCallsSuppressed + 1
end

function FleeEscape.recordDirtyEvent(reason)
  counters.boundedFleePlannerDirtyEvents
    = counters.boundedFleePlannerDirtyEvents + 1
  local key = "dirtyBy" .. tostring(reason or "")
  if counters[key] ~= nil then counters[key] = counters[key] + 1 end
  if reason == "ThreatIdChange" or reason == "ThreatGeometryChange" then
    counters.dirtyByThreatChange = counters.dirtyByThreatChange + 1
  elseif reason == "SocialVectorChange" then
    counters.dirtyBySocialVector = counters.dirtyBySocialVector + 1
  elseif reason == "BlockerReplacement" then
    counters.dirtyByBlockerReplacement = counters.dirtyByBlockerReplacement + 1
    counters.dirtyByBlockerMovement = counters.dirtyByBlockerMovement + 1
  end
end

function FleeEscape.recordSocialVectorUpdate(material)
  counters.socialVectorUpdatesObserved = counters.socialVectorUpdatesObserved + 1
  if material then
    counters.socialVectorUpdatesMaterial = counters.socialVectorUpdatesMaterial + 1
  else
    counters.socialVectorUpdatesIgnoredAsEquivalent
      = counters.socialVectorUpdatesIgnoredAsEquivalent + 1
  end
end

local DIRECTIONS = {
  { direction = "UP", dx = 0, dy = -1 },
  { direction = "DOWN", dx = 0, dy = 1 },
  { direction = "LEFT", dx = -1, dy = 0 },
  { direction = "RIGHT", dx = 1, dy = 0 }
}

local function cellKey(position)
  return WorldSemantics.cellKey(position.cellX, position.cellY)
end

local function distance(left, right)
  return math.max(
    math.abs(left.cellX - right.cellX),
    math.abs(left.cellY - right.cellY)
  )
end

local function recentVisitCount(recentCells, position)
  local key = cellKey(position)
  local count = 0
  for _, cell in ipairs(recentCells or {}) do
    if cell.key == key then count = count + 1 end
  end
  return count
end

local function stableHash(entity, position, firstDirection)
  local hash = math.abs(math.floor(entity and entity.personalitySeed or 0)) % 2147483647
  local value = tostring(entity and entity.id or "") .. ":"
    .. cellKey(position) .. ":" .. tostring(firstDirection or "")
  for index = 1, #value do
    hash = (hash * 131 + value:byte(index)) % 2147483647
  end
  return hash
end

local function directionTie(entity, position, firstDirection)
  local identity = tostring(entity and entity.id or "")
  local identitySum = math.abs(math.floor(entity and entity.personalitySeed or 0))
  for index = 1, #identity do identitySum = identitySum + identity:byte(index) end
  local preferred = identitySum % #DIRECTIONS + 1
  local directionIndex = 1
  for index, direction in ipairs(DIRECTIONS) do
    if direction.direction == firstDirection then directionIndex = index break end
  end
  local directionalRank = (directionIndex - preferred) % #DIRECTIONS
  return directionalRank * 2147483647 + stableHash(entity, position, firstDirection)
end

local function traversalOptions(entity)
  return {
    capabilities = TraversalCapabilities.forEntity(entity),
    allowedModes = { WALK = true }
  }
end

local function staticNeighbors(entity, semantics, position, threatPosition)
  local neighbors = {}
  local options = traversalOptions(entity)
  local threatKey = threatPosition and cellKey(threatPosition) or nil
  for _, direction in ipairs(DIRECTIONS) do
    local destination = {
      cellX = position.cellX + direction.dx,
      cellY = position.cellY + direction.dy
    }
    local legal = cellKey(destination) ~= threatKey
      and TraversalEvaluator.evaluateAdjacent(entity, semantics, position, destination, options).legal
    if legal then
      neighbors[#neighbors + 1] = {
        direction = direction.direction,
        position = destination
      }
    end
  end
  return neighbors
end

function FleeEscape.analyzeLocal(entity, semantics, position, threatPosition, options)
  local settings = options or {}
  local currentDistance = distance(position, threatPosition)
  local candidates = {}
  local useful = 0
  local traversal = traversalOptions(entity)
  local threatKey = cellKey(threatPosition)
  for _, direction in ipairs(DIRECTIONS) do
    local destination = {
      cellX = position.cellX + direction.dx,
      cellY = position.cellY + direction.dy
    }
    local destinationKey = cellKey(destination)
    local threatForbidden = destinationKey == threatKey
    local staticLegal = not threatForbidden
      and TraversalEvaluator.evaluateAdjacent(entity, semantics, position, destination, traversal).legal
    local afterDistance = distance(destination, threatPosition)
    local record = settings.rejectedDirections and settings.rejectedDirections[direction.direction]
    local rejected = NavigationEpisode.rejectionMatches(
      record, position, settings.mapId)
    local occupied = settings.occupiedCells and settings.occupiedCells[destinationKey] == true
    local recentVisits = recentVisitCount(settings.recentCells, destination)
    local threatDelta = afterDistance - currentDistance
    if staticLegal and threatDelta > 0 and not rejected and not occupied then useful = useful + 1 end
    candidates[#candidates + 1] = {
      direction = direction.direction,
      destination = destination,
      staticLegal = staticLegal,
      threatForbidden = threatForbidden,
      occupied = occupied,
      threatDistanceBefore = currentDistance,
      threatDistanceAfter = afterDistance,
      threatDelta = threatDelta,
      recentCellPenalty = recentVisits,
      immediateReversalPenalty = recentVisits > 0,
      rejected = rejected
    }
  end
  return {
    currentThreatDistance = currentDistance,
    usefulMoveCount = useful,
    candidates = candidates
  }
end

local function endpointQuality(entity, semantics, node, startDistance, threatPosition, settings)
  local endpointDistance = distance(node.position, threatPosition)
  local gain = endpointDistance - startDistance
  if gain <= 0 then return nil end

  local neighbors = staticNeighbors(entity, semantics, node.position, threatPosition)
  local mobility = #neighbors
  local onward = 0
  for _, neighbor in ipairs(neighbors) do
    if distance(neighbor.position, threatPosition) > endpointDistance then
      onward = onward + 1
    end
  end
  local firstDirection = node.firstDirection
  local firstDelta = node.firstThreatDelta or 0
  if firstDelta < 0 and gain < 2 then return nil end

  local congestion = 0
  for _, neighbor in ipairs(neighbors) do
    if settings.occupiedCells and settings.occupiedCells[cellKey(neighbor.position)] then
      congestion = congestion + 1
    end
  end
  if settings.occupiedCells and settings.occupiedCells[cellKey(node.position)] then
    congestion = congestion + 2
  end
  local recentPenalty = recentVisitCount(settings.recentCells, node.position)
  local deadEndPenalty = mobility <= 1 and 30 or 0
  local headingAlignment = 0
  if settings.preferredHeading and firstDirection then
    for _, direction in ipairs(DIRECTIONS) do
      if direction.direction == firstDirection then
        headingAlignment = direction.dx * (settings.preferredHeading.dx or 0)
          + direction.dy * (settings.preferredHeading.dy or 0)
        break
      end
    end
  end
  local score = gain * 40 + onward * 18 + mobility * 8
    - node.depth * 3 - recentPenalty * 15 - (node.pathRecentPenalty or 0)
    - congestion * 12 - deadEndPenalty
    - (firstDelta < 0 and 8 or 0) + headingAlignment * 4
  return {
    score = score,
    endpointThreatDistance = endpointDistance,
    endpointMobility = mobility,
    onwardAwayMoves = onward,
    congestion = congestion,
    recentPenalty = recentPenalty,
    pathRecentPenalty = node.pathRecentPenalty or 0,
    firstThreatDelta = firstDelta,
    temporaryThreatRegression = firstDelta < 0,
    headingAlignment = headingAlignment,
    tie = directionTie(entity, node.position, firstDirection)
  }
end

local function better(candidate, best)
  if not best then return true end
  if candidate.quality.score ~= best.quality.score then
    return candidate.quality.score > best.quality.score
  end
  return candidate.quality.tie < best.quality.tie
end

function FleeEscape.plan(entity, semantics, start, threatPosition, options)
  counters.boundedFleePlannerCalls = counters.boundedFleePlannerCalls + 1
  if not entity or not semantics or not start or not threatPosition then return nil end
  local settings = options or {}
  local maxDepth = settings.maxDepth or 6
  local maxExpansions = settings.maxExpansions or 96
  local currentOccupiedCells = settings.currentOccupiedCells or settings.occupiedCells
  local startDistance = distance(start, threatPosition)
  local best, expansions = BoundedSearch.run({
    start = start,
    maxDepth = maxDepth,
    maxExpansions = maxExpansions,
    key = cellKey,
    evaluate = function(node)
      if node.depth > 0 then
      local quality = endpointQuality(entity, semantics, node, startDistance, threatPosition, settings)
      if quality then
          return { node = node, quality = quality }
        end
      end
      return nil
    end,
    better = better,
    neighbors = function(node)
      local neighbors = {}
      for _, neighbor in ipairs(staticNeighbors(entity, semantics, node.position, threatPosition)) do
        local destinationKey = cellKey(neighbor.position)
        local firstStep = node.depth == 0
        local dynamicallyBlocked = firstStep
          and currentOccupiedCells
          and currentOccupiedCells[destinationKey] == true
          and not (settings.vacatingCells and settings.vacatingCells[destinationKey])
        local claimCost = firstStep and settings.movementClaims
          and settings.movementClaims:stepCost(
            entity.id, node.position.cellX, node.position.cellY,
            neighbor.position.cellX, neighbor.position.cellY) or 0
        local rejected = firstStep
          and settings.rejectedDirections
          and NavigationEpisode.rejectionMatches(
            settings.rejectedDirections[neighbor.direction], node.position,
            settings.mapId)
        if not dynamicallyBlocked and not rejected then
          local nextDistance = distance(neighbor.position, threatPosition)
          neighbors[#neighbors + 1] = {
            position = neighbor.position,
            firstDirection = node.firstDirection or neighbor.direction,
            firstThreatDelta = node.firstThreatDelta or (nextDistance - startDistance),
            pathRecentPenalty = (node.pathRecentPenalty or 0)
              + recentVisitCount(settings.recentCells, neighbor.position) * 18
              + (settings.previousCellKey == destinationKey and 30 or 0)
              + claimCost
              + ((settings.dynamicBlockedBottlenecks
                and settings.dynamicBlockedBottlenecks[destinationKey] or 0) * 30),
            action = {
              mode = "WALK",
              direction = neighbor.direction,
              source = { cellX = node.position.cellX, cellY = node.position.cellY },
              destination = { cellX = neighbor.position.cellX, cellY = neighbor.position.cellY }
            }
          }
        end
      end
      return neighbors
    end
  })

  if not best then return nil end
  local actions = BoundedSearch.reconstruct(best.node)
  counters.boundedFleeRouteObjectsCreated
    = counters.boundedFleeRouteObjectsCreated + 1
  return {
    actions = actions,
    index = 1,
    endpoint = { cellX = best.node.position.cellX, cellY = best.node.position.cellY },
    endpointSafetyScore = best.quality.score,
    endpointThreatDistance = best.quality.endpointThreatDistance,
    endpointMobility = best.quality.endpointMobility,
    onwardAwayMoves = best.quality.onwardAwayMoves,
    nextStepThreatDelta = best.quality.firstThreatDelta,
    temporaryThreatRegression = best.quality.temporaryThreatRegression,
    recentPathPenalty = best.quality.pathRecentPenalty,
    expansions = expansions
  }
end

return FleeEscape