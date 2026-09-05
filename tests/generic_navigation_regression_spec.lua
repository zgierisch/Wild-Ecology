local Controller = require("src.behavior.controller")
local NavigationExecution = require("src.navigation.navigation_execution")
local SpatialGoal = require("src.behavior.spatial_goal")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function semantics(mapId, rows)
  return WorldSemantics.fromOverview({
    mapId = mapId,
    width = #rows[1],
    height = #rows,
    rows = rows
  })
end

local function newActor(id, behavior, targetId, destination)
  return {
    id = id,
    personalitySeed = 73,
    ecology = { locomotion = { WALK = true } },
    temperament = { curiosity = 0.8, sociability = 0.8, boldness = 0.5 },
    rawStats = { independence = 0.2 },
    runtimeState = {
      state = behavior,
      stateEnteredTick = 0,
      targetEntityId = targetId,
      targetDestination = behavior == "TARGET" and {
        id = "baseline_destination",
        cellX = destination.cellX,
        cellY = destination.cellY
      } or nil,
      motion = { active = false },
      rejectedMoves = {}
    }
  }
end

local function runCase(case)
  local position = { cellX = case.start.cellX, cellY = case.start.cellY }
  local actor = newActor(case.id, case.behavior, case.targetId, case.destination)
  local occupiedCells = {}
  for key, value in pairs(case.occupiedCells or {}) do occupiedCells[key] = value end
  local metrics = {
    movementRequests = 0,
    successfulSteps = 0,
    staticRejections = 0,
    dynamicRejections = 0,
    repeatedIdenticalAttempts = 0,
    plannerCalls = 0,
    replans = 0,
    routeLength = 0
  }
  local priorAttempt

  for tick = 1, (case.maxTicks or 24) do
    local context = {
      executionOnly = true,
      hasTarget = case.targetId ~= nil,
      purposefulTarget = case.targetId ~= nil,
      position = position,
      mapId = case.map.mapId,
      worldSemantics = case.map,
      targetPositions = case.targetId and {
        [case.targetId] = case.destination
      } or {},
      occupiedCells = occupiedCells,
      currentOccupiedCells = occupiedCells,
      occupancyDetails = {},
      goalRadius = case.goalRadius or 1,
      investigateRadius = case.investigateRadius or 3
    }
    Controller.executeCurrentIntent(actor, context, tick)
    local request = actor.runtimeState.movementRequest
    if request and request.direction ~= "STAY" then
      metrics.movementRequests = metrics.movementRequests + 1
      local attempt = table.concat({ position.cellX, position.cellY, request.direction }, ":")
      if attempt == priorAttempt then
        metrics.repeatedIdenticalAttempts = metrics.repeatedIdenticalAttempts + 1
      end
      priorAttempt = attempt
      local destination = {
        cellX = request.destinationX,
        cellY = request.destinationY
      }
      local destinationKey = WorldSemantics.cellKey(destination.cellX, destination.cellY)
      if occupiedCells[destinationKey] then
        request.rejectionReason = "entity"
        metrics.dynamicRejections = metrics.dynamicRejections + 1
      else
        local traversal = TraversalEvaluator.evaluateAdjacent(
          actor, case.map, position, destination, { allowedModes = { WALK = true } })
        if traversal.legal then
          position = destination
          actor.runtimeState.motion = { active = false, justCompleted = true }
          metrics.successfulSteps = metrics.successfulSteps + 1
        else
          request.rejectionReason = "tile"
          actor.runtimeState.rejectedMoves[request.direction] = {
            mapId = case.map.mapId,
            cellX = position.cellX,
            cellY = position.cellY,
            reason = "tile",
            tick = tick
          }
          metrics.staticRejections = metrics.staticRejections + 1
        end
      end
    end
    local dx = math.abs(position.cellX - case.destination.cellX)
    local dy = math.abs(position.cellY - case.destination.cellY)
    local desiredRadius = case.behavior == "TARGET" and 0
      or case.behavior == "INVESTIGATE" and (case.investigateRadius or 3)
      or (case.goalRadius or 1)
    if math.max(dx, dy) <= desiredRadius then break end
    if actor.runtimeState.navigation then
      metrics.plannerCalls = actor.runtimeState.navigation.plannerCalls or metrics.plannerCalls
      metrics.replans = actor.runtimeState.navigation.replans or metrics.replans
      local route = actor.runtimeState.navigation.route
      metrics.routeLength = math.max(metrics.routeLength,
        route and #route.actions or 0)
    end
  end

  local finalDx = math.abs(position.cellX - case.destination.cellX)
  local finalDy = math.abs(position.cellY - case.destination.cellY)
  local finalRadius = case.behavior == "TARGET" and 0
    or case.behavior == "INVESTIGATE" and (case.investigateRadius or 3)
    or (case.goalRadius or 1)
  metrics.goalReached = math.max(finalDx, finalDy) <= finalRadius
  metrics.stationary = metrics.successfulSteps == 0
  metrics.finalBehavior = actor.runtimeState.state
  metrics.finalPosition = position
  return metrics
end

local detourMap = semantics("GENERIC_NAV_DETOUR", {
  ".......",
  ".. ....",
  ".. ....",
  ".. ....",
  "......."
})
local sealedMap = semantics("GENERIC_NAV_SEALED", {
  ".........",
  "..     ..",
  ".. ... ..",
  ".. ... ..",
  ".. ... ..",
  "..     ..",
  "........."
})
local openMap = semantics("GENERIC_NAV_DYNAMIC", {
  ".......",
  ".......",
  ".......",
  ".......",
  "......."
})

local cases = {
  {
    name = "TARGET around obstacle",
    id = "ordinary-target-detour",
    behavior = "TARGET",
    start = { cellX = 1, cellY = 2 },
    destination = { cellX = 5, cellY = 2 },
    map = detourMap,
    expectReached = true
  },
  {
    name = "INVESTIGATE around obstacle",
    id = "ordinary-investigate-detour",
    behavior = "INVESTIGATE",
    targetId = "subject-b",
    start = { cellX = 1, cellY = 2 },
    destination = { cellX = 5, cellY = 2 },
    investigateRadius = 1,
    map = detourMap,
    expectReached = true
  },
  {
    name = "APPROACH non-greedy lateral step",
    id = "ordinary-approach-detour",
    behavior = "APPROACH",
    targetId = "friend-b",
    start = { cellX = 1, cellY = 2 },
    destination = { cellX = 5, cellY = 2 },
    goalRadius = 1,
    map = detourMap,
    expectReached = true
  },
  {
    name = "sealed enclosure",
    id = "ordinary-approach-sealed",
    behavior = "APPROACH",
    targetId = "sealed-friend",
    start = { cellX = 0, cellY = 3 },
    destination = { cellX = 4, cellY = 3 },
    goalRadius = 1,
    map = sealedMap,
    expectReached = false
  },
  {
    name = "dynamic blocker detour",
    id = "ordinary-approach-dynamic",
    behavior = "APPROACH",
    targetId = "friend-c",
    start = { cellX = 1, cellY = 2 },
    destination = { cellX = 5, cellY = 2 },
    goalRadius = 1,
    map = openMap,
    occupiedCells = { [WorldSemantics.cellKey(2, 2)] = true },
    expectReached = true
  }
}

NavigationExecution.resetCounters()
local results = {}
for index, case in ipairs(cases) do
  local result = runCase(case)
  results[index] = result
  io.write(string.format(
    "BASELINE %s requests=%d steps=%d static=%d dynamic=%d repeated=%d planner=%d replans=%d route=%d reached=%s stationary=%s final=%s\n",
    case.name,
    result.movementRequests,
    result.successfulSteps,
    result.staticRejections,
    result.dynamicRejections,
    result.repeatedIdenticalAttempts,
    result.plannerCalls,
    result.replans,
    result.routeLength,
    tostring(result.goalReached),
    tostring(result.stationary),
    tostring(result.finalBehavior)))
end

for index, case in ipairs(cases) do
  assertEquals(results[index].goalReached, case.expectReached,
    case.name .. " should terminate with the expected reachability result")
end

local rejectionActor = newActor("ordinary-static-rejection", "APPROACH",
  "friend-static", { cellX = 5, cellY = 2 })
local rejectionPosition = { cellX = 1, cellY = 2 }
local rejectionContext = {
  executionOnly = true,
  hasTarget = true,
  purposefulTarget = true,
  position = rejectionPosition,
  mapId = openMap.mapId,
  worldSemantics = openMap,
  targetPositions = { ["friend-static"] = { cellX = 5, cellY = 2 } },
  occupiedCells = {},
  currentOccupiedCells = {},
  occupancyDetails = {},
  goalRadius = 1
}
Controller.executeCurrentIntent(rejectionActor, rejectionContext, 1)
assertEquals(rejectionActor.runtimeState.movementRequest.direction, "RIGHT",
  "static rejection fixture should first choose the direct local step")
local rejectedRequest = rejectionActor.runtimeState.movementRequest
rejectedRequest.rejectionReason = "tile"
rejectionActor.runtimeState.rejectedMoves.RIGHT = {
  mapId = openMap.mapId,
  cellX = rejectionPosition.cellX,
  cellY = rejectionPosition.cellY,
  reason = "tile",
  tick = 1
}
Controller.executeCurrentIntent(rejectionActor, rejectionContext, 2)
assertEquals(rejectionActor.runtimeState.movementRequest.direction == "UP"
  or rejectionActor.runtimeState.movementRequest.direction == "DOWN", true,
  "new actuator topology evidence should trigger an alternate ordinary route")
assertEquals(rejectionActor.runtimeState.navigation.replanReason,
  "STATIC_REJECTION",
  "ordinary navigation should retain the exact static replan trigger")

local performance = NavigationExecution.getCounters()
io.write(string.format(
  "AFTER_NAVIGATION plannerCalls=%d suppressed=%d localSteps=%d routeSteps=%d replans=%d expansions=%d\n",
  performance.plannerCalls,
  performance.plannerCallsSuppressed,
  performance.localSteeringSteps,
  performance.routeFollowingSteps,
  performance.replans,
  performance.searchNodeExpansions))
assertEquals(performance.plannerCalls >= 6, true,
  "the obstacle matrix and learned rejection should invoke bounded planning")
assertEquals(performance.localSteeringSteps > 0, true,
  "uncomplicated movement should retain local steering as a fast path")
assertEquals(performance.routeFollowingSteps > performance.plannerCalls, true,
  "routes should be followed across steps rather than replanned every tick")

return true