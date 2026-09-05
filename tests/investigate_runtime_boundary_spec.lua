local Controller = require("src.behavior.controller")
local IntentEpisode = require("src.behavior.intent_episode")
local SpatialGoal = require("src.behavior.spatial_goal")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function semantics()
  return WorldSemantics.fromOverview({
    mapId = "INVESTIGATE_BOUNDARY",
    width = 9,
    height = 5,
    rows = {
      ".........",
      ".........",
      ".........",
      ".........",
      "........."
    }
  })
end

local function actor(id, targetId)
  return {
    id = id,
    ecology = { locomotion = { WALK = true } },
    temperament = { curiosity = 1, sociability = 0.5, boldness = 0.5 },
    rawStats = { independence = 0.2 },
    relationships = {},
    runtimeState = {
      state = "INVESTIGATE",
      stateEnteredTick = 0,
      targetEntityId = targetId,
      motion = { active = false }
    }
  }
end

local function context(position, targetId, targetPosition)
  return {
    executionOnly = true,
    hasTarget = true,
    purposefulTarget = true,
    position = position,
    mapId = "INVESTIGATE_BOUNDARY",
    worldSemantics = semantics(),
    targetPositions = { [targetId] = targetPosition },
    occupiedCells = {
      [WorldSemantics.cellKey(targetPosition.cellX, targetPosition.cellY)] = true
    },
    currentOccupiedCells = {
      [WorldSemantics.cellKey(targetPosition.cellX, targetPosition.cellY)] = true
    },
    investigateRadius = 3,
    goalRadius = 1
  }
end

-- Already in range: navigation and intent must agree without locomotion.
do
  local targetId = "nearby-target"
  local entity = actor("already-near", targetId)
  local decisionContext = context(
    { cellX = 1, cellY = 2 }, targetId, { cellX = 4, cellY = 2 })
  local goal = SpatialGoal.proximity(targetId,
    decisionContext.targetPositions[targetId], 3, {
      allowOverlap = false,
      mapId = decisionContext.mapId,
      source = "investigate"
    })
  assertEquals(SpatialGoal.isSatisfied(goal, decisionContext.position), true,
    "INVESTIGATE spatial goal should be satisfied at Chebyshev radius 3")
  Controller.executeCurrentIntent(entity, decisionContext, 100)
  assertEquals(entity.runtimeState.movementRequest, nil,
    "an already-satisfied INVESTIGATE should request no locomotion")
  assertEquals(entity.runtimeState.intentEpisode.status, "SATISFIED",
    "intent satisfaction must match the INVESTIGATE spatial goal")
end

-- Reaching the boundary: the exact goal predicate must be shared.
do
  local targetId = "boundary-target"
  local entity = actor("reaches-boundary", targetId)
  local targetPosition = { cellX = 6, cellY = 2 }
  local outside = context(
    { cellX = 1, cellY = 2 }, targetId, targetPosition)
  Controller.executeCurrentIntent(entity, outside, 200)
  assertEquals(entity.runtimeState.intentEpisode.status, "ACTIVE",
    "an out-of-range investigation should remain active")

  local boundaryPosition = { cellX = 3, cellY = 2 }
  local boundary = context(boundaryPosition, targetId, targetPosition)
  local goal = SpatialGoal.proximity(targetId, targetPosition, 3, {
    allowOverlap = false,
    mapId = boundary.mapId,
    source = "investigate"
  })
  assertEquals(SpatialGoal.isSatisfied(goal, boundaryPosition), true,
    "SpatialGoal should accept the exact INVESTIGATE radius")
  IntentEpisode.observe(entity, "INVESTIGATE", targetId, nil, boundary, 201, false)
  assertEquals(entity.runtimeState.intentEpisode.status, "SATISFIED",
    "IntentEpisode should accept the same exact INVESTIGATE radius")
  assertEquals(entity.runtimeState.intentEpisode.progress > 0, true,
    "reaching investigation range should record meaningful progress")
end

return true
