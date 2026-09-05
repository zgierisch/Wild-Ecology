local WorldSemantics = require("src.world.world_semantics")
local BoundedSearch = require("src.navigation.bounded_search")
local TraversalCapabilities = require("src.navigation.traversal_capabilities")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")

local NavigationPlanner = {}

local spawnViabilityCache = setmetatable({}, { __mode = "k" })

local DIRECTIONS = {
  { direction = "UP", dx = 0, dy = -1 },
  { direction = "LEFT", dx = -1, dy = 0 },
  { direction = "RIGHT", dx = 1, dy = 0 },
  { direction = "DOWN", dx = 0, dy = 1 }
}

local DIRECTION_VECTOR = {
  NORTH = { dx = 0, dy = -1 }, UP = { dx = 0, dy = -1 },
  SOUTH = { dx = 0, dy = 1 }, DOWN = { dx = 0, dy = 1 },
  WEST = { dx = -1, dy = 0 }, LEFT = { dx = -1, dy = 0 },
  EAST = { dx = 1, dy = 0 }, RIGHT = { dx = 1, dy = 0 }
}

local function cellKey(position)
  return WorldSemantics.cellKey(position.cellX, position.cellY)
end

local function intersectModes(allowedModes, executableModes)
  local modes = {}
  for mode, executable in pairs(executableModes or TraversalCapabilities.executableModes()) do
    if executable and (allowedModes == nil or allowedModes[mode] == true) then
      modes[mode] = true
    end
  end
  return modes
end

local function directionalProgress(start, position, direction)
  local vector = DIRECTION_VECTOR[direction] or { dx = 0, dy = 0 }
  return (position.cellX - start.cellX) * vector.dx + (position.cellY - start.cellY) * vector.dy
end

local function positionDistance(left, right)
  return math.abs(left.cellX - right.cellX) + math.abs(left.cellY - right.cellY)
end

local function betterFrontier(candidate, best, start, goal, endpointScore)
  if not best then
    return true
  end
  if endpointScore then
    local candidateScore = endpointScore(candidate.position, candidate)
    local bestScore = endpointScore(best.position, best)
    if candidateScore ~= bestScore then return candidateScore > bestScore end
  end
  if goal.kind == "DIRECTIONAL_REGION" then
    local candidateProgress = directionalProgress(start, candidate.position, goal.direction)
    local bestProgress = directionalProgress(start, best.position, goal.direction)
    if candidateProgress ~= bestProgress then
      return candidateProgress > bestProgress
    end
  elseif goal.kind == "POSITION" or goal.kind == "PROXIMITY" then
    local candidateDistance = positionDistance(candidate.position, goal.destination)
    local bestDistance = positionDistance(best.position, goal.destination)
    if candidateDistance ~= bestDistance then
      return candidateDistance < bestDistance
    end
  end
  if candidate.depth ~= best.depth then
    return candidate.depth < best.depth
  end
  if (candidate.firstStepClaimCost or 0) ~= (best.firstStepClaimCost or 0) then
    return (candidate.firstStepClaimCost or 0) < (best.firstStepClaimCost or 0)
  end
  return cellKey(candidate.position) < cellKey(best.position)
end

function NavigationPlanner.plan(entity, semantics, start, goal, options)
  local settings = options or {}
  if not semantics or not start or not goal or goal.kind == "SEARCH" then
    return nil
  end
  local maxDepth = settings.maxDepth or 10
  local maxExpansions = settings.maxExpansions or 128
  local capabilities = settings.capabilities or TraversalCapabilities.forEntity(entity)
  local planningModes = intersectModes(settings.allowedModes, settings.executableModes)
  local function goalSatisfied(position)
    if settings.isGoalSatisfied then
      return settings.isGoalSatisfied(position, goal) == true
    end
    local goalRadius = goal.kind == "PROXIMITY" and (goal.radius or 1) or 0
    return (goal.kind == "POSITION" or goal.kind == "PROXIMITY")
      and positionDistance(position, goal.destination) <= goalRadius
  end
  local reachedGoal = false
  local best, expansions = BoundedSearch.run({
    start = start,
    includeStart = true,
    maxDepth = maxDepth,
    maxExpansions = maxExpansions,
    key = cellKey,
    evaluate = function(node)
      if goalSatisfied(node.position) then reachedGoal = true end
      return node
    end,
    better = function(candidate, currentBest)
      if goalSatisfied(candidate.position) ~= goalSatisfied(currentBest.position) then
        return goalSatisfied(candidate.position)
      end
      return betterFrontier(candidate, currentBest, start, goal, settings.endpointScore)
    end,
    stop = function(node)
      return goalSatisfied(node.position)
    end,
    neighbors = function(node)
      local neighbors = {}
      for _, direction in ipairs(DIRECTIONS) do
        local destination = {
          cellX = node.position.cellX + direction.dx,
          cellY = node.position.cellY + direction.dy
        }
        local destinationKey = cellKey(destination)
        local edgeKey = WorldSemantics.edgeKey(node.position.cellX, node.position.cellY, destination.cellX, destination.cellY)
        local dynamicallyBlocked = settings.dynamicBlockedCells
          and settings.dynamicBlockedCells[destinationKey] == true
        if not dynamicallyBlocked and not (settings.blockedEdges and settings.blockedEdges[edgeKey]) then
          local traversal = TraversalEvaluator.evaluateAdjacent(entity, semantics, node.position, destination, {
            capabilities = capabilities,
            allowedModes = planningModes
          })
          if traversal.legal then
            local firstStepClaimCost = node.depth == 0 and settings.movementClaims
              and settings.movementClaims:stepCost(
                entity.id, node.position.cellX, node.position.cellY,
                destination.cellX, destination.cellY) or 0
            neighbors[#neighbors + 1] = {
              position = destination,
              firstStepClaimCost = node.firstStepClaimCost or firstStepClaimCost,
              action = {
                mode = traversal.mode,
                source = { cellX = node.position.cellX, cellY = node.position.cellY },
                direction = direction.direction,
                destination = destination,
                cost = traversal.cost
              }
            }
          end
        end
      end
      if planningModes.TELEPORT == true and capabilities.TELEPORT then
        local maxRange = type(capabilities.TELEPORT) == "table" and capabilities.TELEPORT.maxRange or 4
        for y = node.position.cellY - maxRange, node.position.cellY + maxRange do
          for x = node.position.cellX - maxRange, node.position.cellX + maxRange do
            local destination = { cellX = x, cellY = y }
            local destinationKey = cellKey(destination)
            if not (settings.dynamicBlockedCells
              and settings.dynamicBlockedCells[destinationKey]) then
              local traversal = TraversalEvaluator.evaluateTeleport(entity, semantics, node.position, destination, {
                capabilities = capabilities,
                allowedModes = planningModes
              })
              if traversal.legal then
                neighbors[#neighbors + 1] = {
                  position = destination,
                  action = {
                    mode = "TELEPORT",
                    source = { cellX = node.position.cellX, cellY = node.position.cellY },
                    destination = destination,
                    cost = traversal.cost
                  }
                }
              end
            end
          end
        end
      end
      return neighbors
    end
  })

  local actions = BoundedSearch.reconstruct(best)
  if #actions == 0 then
    return nil
  end
  return {
    goalKind = goal.kind,
    goalSource = goal.source,
    reachedGoal = reachedGoal or goalSatisfied(best.position),
    waypoint = { cellX = best.position.cellX, cellY = best.position.cellY },
    actions = actions,
    index = 1,
    expansions = expansions
  }
end

function NavigationPlanner.isSpawnViable(entity, semantics, position, options)
  if not semantics or not position
    or not WorldSemantics.isLandingAllowed(semantics, position.cellX, position.cellY, "WALK") then
    return false
  end
  if not WorldSemantics.isOutdoorMap(semantics) then
    return true
  end
  local capabilities = TraversalCapabilities.forEntity(entity)
  local executableModes = options and options.executableModes or TraversalCapabilities.executableModes()
  local allowedModes = intersectModes(options and options.allowedModes, executableModes)
  local useCache = options == nil
  local cacheKey = capabilities.WALK == true and "WALK" or "NO_WALK"
  local cachedByMode = nil
  local cached = nil
  if useCache then
    cachedByMode = spawnViabilityCache[semantics]
    cached = cachedByMode and cachedByMode[cacheKey]
  end
  if useCache and not cached then
    cached = {}
    local queue = {}
    local head = 1
    for y = 0, (semantics.height or 0) - 1 do
      for x = 0, (semantics.width or 0) - 1 do
        local transition = WorldSemantics.transitionAt(semantics, x, y)
        if transition and transition.kind == "OVERWORLD_EXIT"
          and WorldSemantics.isLandingAllowed(semantics, x, y, "WALK") then
          local exit = { cellX = x, cellY = y }
          local exitKey = cellKey(exit)
          cached[exitKey] = true
          queue[#queue + 1] = exit
        end
      end
    end
    while head <= #queue do
      local current = queue[head]
      head = head + 1
      for _, direction in ipairs(DIRECTIONS) do
        local predecessor = {
          cellX = current.cellX - direction.dx,
          cellY = current.cellY - direction.dy
        }
        local predecessorKey = cellKey(predecessor)
        if not cached[predecessorKey]
          and TraversalEvaluator.evaluateAdjacent(entity, semantics, predecessor, current, {
            capabilities = capabilities,
            allowedModes = allowedModes
          }).legal then
          cached[predecessorKey] = true
          queue[#queue + 1] = predecessor
        end
      end
    end
    cachedByMode = cachedByMode or {}
    cachedByMode[cacheKey] = cached
    spawnViabilityCache[semantics] = cachedByMode
  end
  if cached then
    return cached[cellKey(position)] == true
  end
  local queue = { { cellX = position.cellX, cellY = position.cellY } }
  local head = 1
  local visited = { [cellKey(position)] = true }
  while head <= #queue do
    local current = queue[head]
    head = head + 1
    local transition = WorldSemantics.transitionAt(semantics, current.cellX, current.cellY)
    if transition and transition.kind == "OVERWORLD_EXIT" then
      return true
    end
    for _, direction in ipairs(DIRECTIONS) do
      local destination = { cellX = current.cellX + direction.dx, cellY = current.cellY + direction.dy }
      local destinationKey = cellKey(destination)
      if not visited[destinationKey] and TraversalEvaluator.evaluateAdjacent(entity, semantics, current, destination, {
        capabilities = capabilities,
        allowedModes = allowedModes
      }).legal then
        visited[destinationKey] = true
        queue[#queue + 1] = destination
      end
    end
  end
  return false
end

function NavigationPlanner.hasReachableOverworldExit(entity, semantics, position, options)
  if not WorldSemantics.isOutdoorMap(semantics) then
    return false
  end
  return NavigationPlanner.isSpawnViable(entity, semantics, position, options)
end

NavigationPlanner.hasReachableRouteExit = NavigationPlanner.hasReachableOverworldExit

return NavigationPlanner