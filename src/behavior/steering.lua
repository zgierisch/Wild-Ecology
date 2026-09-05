local SpatialGoal = require("src.behavior.spatial_goal")

local Steering = {}

local DIRECTIONS = {
  { direction = "UP", dx = 0, dy = -1 },
  { direction = "DOWN", dx = 0, dy = 1 },
  { direction = "LEFT", dx = -1, dy = 0 },
  { direction = "RIGHT", dx = 1, dy = 0 }
}

local function distanceToGoal(position, goal)
  local dx = math.abs(position.cellX - goal.targetPosition.cellX)
  local dy = math.abs(position.cellY - goal.targetPosition.cellY)
  return math.max(dx, dy)
end

local function ranksForGoal(currentDistance, candidateDistance, goal)
  if goal and goal.objective == "AWAY" then
    return -candidateDistance
  end
  return candidateDistance
end

local function recentVisitCount(recentCells, position)
  local key = tostring(position.cellX) .. "," .. tostring(position.cellY)
  local count = 0
  for _, cell in ipairs(recentCells or {}) do
    if cell.key == key then
      count = count + 1
    end
  end
  return count
end

local function headingMetrics(candidate, nextPosition, settings)
  local heading = settings.desiredHeading
  if not heading then return 0, math.huge end
  local alignment = candidate.dx * (heading.dx or 0) + candidate.dy * (heading.dy or 0)
  local residual = settings.headingResidual
  if not residual then return alignment, -alignment end
  local demand = candidate.dx * (residual.dx or 0) + candidate.dy * (residual.dy or 0)
  return alignment, -demand
end

function Steering.request(position, goal, options)
  local settings = options or {}
  local request = {
    direction = "STAY",
    traversalMode = "NONE",
    targetEntityId = goal and goal.targetEntityId or nil,
    goalKind = goal and goal.kind or nil,
    reason = "NO_LEGAL_STEP"
  }

  if not position or not goal or not goal.targetPosition then
    return request
  end
  if SpatialGoal.isSatisfied(goal, position) then
    request.reason = "GOAL_SATISFIED"
    return request
  end

  local rejected = settings.rejectedDirections or {}
  local occupiedCells = settings.occupiedCells or {}
  local currentOccupiedCells = settings.currentOccupiedCells or occupiedCells
  local function isRejected(direction)
    local record = rejected[direction]
    if record == true then
      return true
    end
    return type(record) == "table"
      and record.mapId == settings.mapId
      and record.cellX == position.cellX
      and record.cellY == position.cellY
  end
  local ranked = {}
  local currentDistance = distanceToGoal(position, goal)
  for _, candidate in ipairs(DIRECTIONS) do
    local nextPosition = {
      cellX = position.cellX + candidate.dx,
      cellY = position.cellY + candidate.dy
    }
    local candidateDistance = distanceToGoal(nextPosition, goal)
    if not settings.directOnly or candidateDistance < currentDistance then
      local headingAlignment, headingError = headingMetrics(candidate, nextPosition, settings)
      ranked[#ranked + 1] = {
        direction = candidate.direction,
        distance = ranksForGoal(currentDistance, candidateDistance, goal),
        rejected = isRejected(candidate.direction),
        occupied = currentOccupiedCells[tostring(nextPosition.cellX) .. "," .. tostring(nextPosition.cellY)] == true,
        claimCost = settings.movementClaims and settings.movementClaims:stepCost(
          settings.actorId, position.cellX, position.cellY,
          nextPosition.cellX, nextPosition.cellY) or 0,
        recentVisits = recentVisitCount(settings.recentCells, nextPosition),
        immediateReversal = settings.previousCellKey == tostring(nextPosition.cellX) .. "," .. tostring(nextPosition.cellY),
        movesTowardThreat = goal.objective == "AWAY" and candidateDistance < currentDistance or false,
        headingAlignment = headingAlignment,
        headingError = headingError,
        priority = #ranked + 1
      }
    end
  end

  table.sort(ranked, function(left, right)
    if left.rejected ~= right.rejected then
      return not left.rejected
    end
    if left.occupied ~= right.occupied then
      return not left.occupied
    end
    if left.claimCost ~= right.claimCost then
      return left.claimCost < right.claimCost
    end
    if left.immediateReversal ~= right.immediateReversal then
      return not left.immediateReversal
    end
    if left.recentVisits ~= right.recentVisits then
      return left.recentVisits < right.recentVisits
    end
    if left.movesTowardThreat ~= right.movesTowardThreat then
      return not left.movesTowardThreat
    end
    if settings.desiredHeading and left.headingError ~= right.headingError then
      return left.headingError < right.headingError
    end
    if left.distance ~= right.distance then
      return left.distance < right.distance
    end
    return left.priority < right.priority
  end)

  request.rankedDirections = {}
  for _, candidate in ipairs(ranked) do
    request.rankedDirections[#request.rankedDirections + 1] = candidate.direction
  end
  if ranked[1] and not ranked[1].rejected and not ranked[1].occupied then
    request.direction = ranked[1].direction
    request.traversalMode = "WALK"
    request.destinationX = position.cellX + (request.direction == "LEFT" and -1 or request.direction == "RIGHT" and 1 or 0)
    request.destinationY = position.cellY + (request.direction == "UP" and -1 or request.direction == "DOWN" and 1 or 0)
    request.reason = nil
    request.headingAlignmentScore = ranked[1].headingAlignment
    request.headingResidualScore = -ranked[1].headingError
    request.headingAlignments = {
      UP = -(settings.desiredHeading and settings.desiredHeading.dy or 0),
      DOWN = settings.desiredHeading and settings.desiredHeading.dy or 0,
      LEFT = -(settings.desiredHeading and settings.desiredHeading.dx or 0),
      RIGHT = settings.desiredHeading and settings.desiredHeading.dx or 0
    }
  elseif ranked[1] and ranked[1].occupied then
    request.reason = "DYNAMIC_OCCUPANCY"
  end
  return request
end

return Steering