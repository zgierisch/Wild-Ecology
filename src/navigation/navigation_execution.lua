local NavigationPlanner = require("src.navigation.navigation_planner")
local NavigationEpisode = require("src.navigation.navigation_episode")
local SpatialGoal = require("src.behavior.spatial_goal")
local Steering = require("src.behavior.steering")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local WorldSemantics = require("src.world.world_semantics")

local NavigationExecution = {}
local diagnosticSink = nil

local counters = {
  plannerCalls = 0,
  plannerCallsSuppressed = 0,
  localSteeringSteps = 0,
  routeFollowingSteps = 0,
  replans = 0,
  searchNodeExpansions = 0
}

local function copyCounters()
  local result = {}
  for key, value in pairs(counters) do result[key] = value end
  return result
end

function NavigationExecution.getCounters()
  return copyCounters()
end

function NavigationExecution.resetCounters()
  for key in pairs(counters) do counters[key] = 0 end
end

function NavigationExecution.setDiagnosticSink(sink)
  diagnosticSink = type(sink) == "function" and sink or nil
end

local function positionKey(position)
  return position and WorldSemantics.cellKey(position.cellX, position.cellY) or "none"
end

function NavigationExecution.emitOccupancyDiagnostic(entity, context, owner, source, destination)
  if not diagnosticSink or not destination then return end
  local key = positionKey(destination)
  diagnosticSink({
    event = "ENTITY_BLOCK_DIAGNOSTIC",
    layer = "PLANNER_OCCUPANCY",
    actorId = entity.id,
    mapId = context.mapId,
    source = source,
    destination = destination,
    targetEntityId = owner.targetEntityId,
    destinationIsTargetCell = false,
    occupancy = context.occupancyDetails and context.occupancyDetails[key] or nil
  })
end

local function sortedKeys(values)
  local keys = {}
  for key, enabled in pairs(values or {}) do
    if enabled then keys[#keys + 1] = key end
  end
  table.sort(keys)
  return table.concat(keys, "|")
end

local function problemSignature(owner, context)
  return table.concat({
    positionKey(context.position),
    tostring(context.mapId or ""),
    sortedKeys(owner.blockedEdges),
    sortedKeys(context.occupiedCells)
  }, ":")
end

local function copyRejectedEdges(runtime, context, blockedEdges)
  for direction, record in pairs(runtime.rejectedMoves or {}) do
    if type(record) == "table"
      and record.mapId == context.mapId
      and record.cellX == context.position.cellX
      and record.cellY == context.position.cellY then
      local dx = direction == "LEFT" and -1 or direction == "RIGHT" and 1 or 0
      local dy = direction == "UP" and -1 or direction == "DOWN" and 1 or 0
      blockedEdges[WorldSemantics.edgeKey(
        context.position.cellX, context.position.cellY,
        context.position.cellX + dx, context.position.cellY + dy)] = true
    end
  end
end

function NavigationExecution.observeResult(owner, runtime, context, tick, priorRequest, stepCompleted)
  if not owner then return end
  if stepCompleted and owner.route then
    local completed = NavigationEpisode.advanceRoute(owner.route)
    owner.lastProgressTick = tick
    owner.noProgressCount = 0
    if completed then
      owner.route = nil
      owner.replanReason = "ROUTE_COMPLETE"
    end
  end
  local rejection = priorRequest and priorRequest.rejectionReason
  if rejection == nil or rejection == "MOVEMENT_ACTIVE" then return end
  owner.noProgressCount = (owner.noProgressCount or 0) + 1
  owner.route = nil
  if rejection == "tile" or rejection == "bounds" then
    owner.blockedEdges = owner.blockedEdges or {}
    if priorRequest.sourceX ~= nil and priorRequest.sourceY ~= nil
      and priorRequest.destinationX ~= nil and priorRequest.destinationY ~= nil then
      owner.blockedEdges[NavigationEpisode.staticEdgeFromRequest(priorRequest)] = true
    end
    owner.replanReason = "STATIC_REJECTION"
  elseif rejection == "entity" then
    owner.replanReason = "DYNAMICALLY_BLOCKED"
  elseif rejection == "SOURCE_POSITION_MISMATCH" then
    owner.replanReason = "SOURCE_POSITION_MISMATCH"
  else
    owner.replanReason = "EXECUTION_REJECTED"
  end
  owner.failedPlanningContext = nil
  counters.replans = counters.replans + 1
end

function NavigationExecution.navigate(entity, context, goal, options)
  local settings = options or {}
  local runtime = entity.runtimeState
  local tick = settings.tick or 0
  if not goal then
    runtime.navigation = nil
    local request = Steering.request(context.position, nil)
    request.issuedTick = tick
    return request, nil
  end
  local signature = settings.ownerGoalSignature or SpatialGoal.signature(goal)
  local owner = runtime.navigation
  local existingSignature = owner
    and (owner.ownerGoalSignature or owner.goalSignature) or nil
  local existingBehavior = owner and (owner.ownerBehavior
    or (owner.goalSignature and "SEEK_FLOCK")) or nil
  local existingTraversalMode = owner and (owner.traversalMode or "WALK") or nil
  if not owner or existingSignature ~= signature
    or existingBehavior ~= settings.ownerBehavior
    or owner.mapId ~= context.mapId
    or existingTraversalMode ~= (goal.traversalMode or "WALK") then
    owner = {
      ownerGoalSignature = signature,
      ownerBehavior = settings.ownerBehavior,
      mapId = context.mapId,
      traversalMode = goal.traversalMode or "WALK",
      goalKind = goal.kind,
      goalSource = goal.source,
      targetEntityId = goal.targetEntityId,
      blockedEdges = {},
      dynamicBlockedEdges = {},
      noProgressCount = 0,
      localSteeringFailures = 0,
      replanReason = "NEW_GOAL",
      goalSatisfactionState = "ACTIVE"
    }
    runtime.navigation = owner
  end
  owner.ownerGoalSignature = signature
  owner.ownerBehavior = settings.ownerBehavior
  owner.traversalMode = owner.traversalMode or goal.traversalMode or "WALK"
  owner.dynamicBlockedEdges = owner.dynamicBlockedEdges or {}
  owner.noProgressCount = owner.noProgressCount or 0
  owner.localSteeringFailures = owner.localSteeringFailures or 0
  owner.goalSignature = settings.ownerGoalSignature or owner.goalSignature

  owner.plannerCalls = owner.plannerCalls or 0
  owner.replans = owner.replans or 0
  local goalSatisfied = settings.isGoalSatisfied or SpatialGoal.isSatisfied
  if goalSatisfied(goal, context.position) then
    owner.route = nil
    owner.goalSatisfactionState = "SATISFIED"
    return {
      direction = "STAY",
      traversalMode = "NONE",
      targetEntityId = goal.targetEntityId,
      goalKind = goal.kind,
      reason = "GOAL_SATISFIED",
      issuedTick = tick
    }, owner
  end

  local action = NavigationEpisode.currentAction(owner.route)
  if action and not NavigationEpisode.sourceMatches(action, context.position) then
    owner.route = nil
    owner.replanReason = "SOURCE_POSITION_MISMATCH"
    owner.replans = owner.replans + 1
    counters.replans = counters.replans + 1
    action = nil
  end
  if action and not settings.deferOccupiedAction and context.occupiedCells
    and context.occupiedCells[positionKey(action.destination)] then
    NavigationExecution.emitOccupancyDiagnostic(entity, context, owner, action.source,
      action.destination)
    owner.route = nil
    owner.replanReason = "DYNAMICALLY_BLOCKED"
    owner.replans = owner.replans + 1
    counters.replans = counters.replans + 1
    action = nil
  end
  if action then
    counters.routeFollowingSteps = counters.routeFollowingSteps + 1
    owner.goalSatisfactionState = "ACTIVE"
    return NavigationEpisode.requestForAction(action, owner.route, {
      targetEntityId = goal.targetEntityId,
      goalKind = owner.goalKind,
      waypoint = owner.route.waypoint,
      tick = tick
    }), owner
  end

  local localRequest = Steering.request(context.position, goal, {
    rejectedDirections = runtime.rejectedMoves,
    mapId = context.mapId,
    occupiedCells = context.occupiedCells,
    currentOccupiedCells = context.currentOccupiedCells,
    movementClaims = context.movementClaims,
    actorId = entity.id
  })
  local localDestination = localRequest.destinationX ~= nil and {
    cellX = localRequest.destinationX,
    cellY = localRequest.destinationY
  } or nil
  local localTraversal = localDestination and context.worldSemantics
    and TraversalEvaluator.evaluateAdjacent(entity, context.worldSemantics,
      context.position, localDestination, { allowedModes = { WALK = true } }) or nil
  local forcePlan = owner.replanReason == "STATIC_REJECTION"
    or owner.replanReason == "SOURCE_POSITION_MISMATCH"
  if not settings.forcePlanner and not forcePlan
    and localRequest.traversalMode == "WALK"
    and (localTraversal == nil or localTraversal.legal)
    and not (context.occupiedCells and context.occupiedCells[positionKey(localDestination)]) then
    localRequest.sourceX = context.position.cellX
    localRequest.sourceY = context.position.cellY
    localRequest.issuedTick = tick
    owner.localSteeringFailures = 0
    owner.goalSatisfactionState = "ACTIVE"
    counters.localSteeringSteps = counters.localSteeringSteps + 1
    return localRequest, owner
  end
  if localDestination and context.occupiedCells
    and context.occupiedCells[positionKey(localDestination)] then
    NavigationExecution.emitOccupancyDiagnostic(entity, context, owner, context.position,
      localDestination)
  end

  owner.localSteeringFailures = (owner.localSteeringFailures or 0) + 1
  if not context.worldSemantics then
    return localRequest, owner
  end
  local failedSignature = problemSignature(owner, context)
  if owner.failedPlanningContext == failedSignature then
    counters.plannerCallsSuppressed = counters.plannerCallsSuppressed + 1
    owner.goalSatisfactionState = "UNREACHABLE"
    return {
      direction = "STAY", traversalMode = "NONE",
      targetEntityId = goal.targetEntityId, goalKind = goal.kind,
      reason = owner.failureReason or "UNREACHABLE_STATIC", issuedTick = tick
    }, owner
  end

  local blockedEdges = {}
  for edge in pairs(owner.blockedEdges or {}) do blockedEdges[edge] = true end
  for edge in pairs(owner.dynamicBlockedEdges or {}) do blockedEdges[edge] = true end
  copyRejectedEdges(runtime, context, blockedEdges)
  counters.plannerCalls = counters.plannerCalls + 1
  owner.plannerCalls = owner.plannerCalls + 1
  local plannerGoal = settings.plannerGoal or {
    kind = goal.kind == "PROXIMITY" and "PROXIMITY" or "POSITION",
    source = goal.source,
    targetEntityId = goal.targetEntityId,
    destination = goal.targetPosition,
    radius = goal.radius
  }
  local route = NavigationPlanner.plan(entity, context.worldSemantics,
    context.position, plannerGoal, {
      maxDepth = settings.maxDepth or context.navigationHorizon or 10,
      maxExpansions = settings.maxExpansions or context.navigationMaxExpansions or 128,
      allowedModes = { WALK = true },
      blockedEdges = blockedEdges,
      dynamicBlockedCells = settings.deferOccupiedAction and nil or context.occupiedCells,
      movementClaims = context.movementClaims,
      isGoalSatisfied = settings.plannerGoalSatisfied or function(position)
        return goalSatisfied(goal, position)
      end
    })
  counters.searchNodeExpansions = counters.searchNodeExpansions
    + (route and route.expansions or settings.maxExpansions or 128)
  if not route then
    owner.failedPlanningContext = failedSignature
    owner.failureReason = "UNREACHABLE_STATIC"
    owner.goalSatisfactionState = "UNREACHABLE"
    return {
      direction = "STAY", traversalMode = "NONE",
      targetEntityId = goal.targetEntityId, goalKind = goal.kind,
      reason = owner.failureReason, issuedTick = tick
    }, owner
  end

  owner.route = route
  owner.waypoint = route.waypoint
  owner.failedPlanningContext = nil
  owner.failureReason = route.reachedGoal and nil or "SEARCH_BUDGET_EXHAUSTED"
  owner.goalSatisfactionState = "ACTIVE"
  action = NavigationEpisode.currentAction(route)
  counters.routeFollowingSteps = counters.routeFollowingSteps + 1
  return NavigationEpisode.requestForAction(action, route, {
    targetEntityId = goal.targetEntityId,
    goalKind = owner.goalKind,
    waypoint = route.waypoint,
    tick = tick
  }), owner
end

return NavigationExecution