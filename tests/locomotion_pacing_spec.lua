local Controller = require("src.behavior.controller")
local LocomotionPolicy = require("src.behavior.locomotion_policy")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function openMap(width)
  local row = string.rep(".", width)
  return WorldSemantics.fromOverview({
    mapId = "COHERENT_LOCOMOTION",
    width = width,
    height = 3,
    rows = { row, row, row }
  })
end

local function actorFor(behavior)
  return {
    id = "coherent-" .. string.lower(behavior),
    species = "PIDGEY",
    ecology = { family = "BIRD", locomotion = { WALK = true } },
    temperament = { curiosity = 0.8, sociability = 0.8, boldness = 0.5 },
    rawStats = { independence = 0.2, active = 0.5 },
    relationships = {},
    runtimeState = {
      state = behavior,
      stateEnteredTick = 0,
      targetEntityId = behavior ~= "TARGET" and "goal" or nil,
      targetDestination = behavior == "TARGET" and {
        id = "target_right", cellX = 30, cellY = 1
      } or nil,
      motion = { active = false },
      rejectedMoves = {}
    }
  }
end

local semantics = openMap(40)
for _, behavior in ipairs({ "TARGET", "INVESTIGATE", "APPROACH", "SEEK_FLOCK" }) do
  local actor = actorFor(behavior)
  local position = { cellX = 1, cellY = 1 }
  local destination = { cellX = 30, cellY = 1 }
  for tick = 1, 8 do
    actor.runtimeState.motion = actor.runtimeState.motion or {}
    actor.runtimeState.motion.active = false
    Controller.executeCurrentIntent(actor, {
      executionOnly = true,
      locomotionPacing = true,
      hasTarget = behavior ~= "TARGET",
      purposefulTarget = behavior ~= "TARGET",
      position = position,
      mapId = semantics.mapId,
      worldSemantics = semantics,
      targetPositions = behavior ~= "TARGET" and { goal = destination } or {},
      occupiedCells = {}, occupancyDetails = {},
      investigateRadius = 1, goalRadius = 1,
      flockSearch = behavior == "SEEK_FLOCK" and {
        utility = 100, isolationPressure = 1, nearbySameSpecies = 0,
        cueSource = "perceived", cuePosition = destination,
        targetEntityId = "goal"
      } or nil
    }, tick)
    local request = actor.runtimeState.movementRequest
    assertEquals(request and request.traversalMode, "WALK",
      behavior .. " should execute a committed journey coherently")
    position = { cellX = request.destinationX, cellY = request.destinationY }
    actor.runtimeState.motion = { active = false, justCompleted = true }
  end
end

local needActor = actorFor("SATISFY_NEED")
needActor.runtimeState.targetEntityId = nil
local needGoal = {
  kind = "POSITION",
  targetPosition = { cellX = 8, cellY = 1 },
  radius = 0,
  alignment = "ANY",
  objective = "TOWARD",
  allowOverlap = true,
  mapId = semantics.mapId,
  traversalMode = "WALK",
  source = "need:THIRST:WATER_ADJACENT"
}
needActor.runtimeState.needOpportunity = {
  driveId = "THIRST",
  semantic = "WATER_ADJACENT",
  goal = needGoal,
  goalSignature = "paced-thirst-goal"
}
Controller.executeCurrentIntent(needActor, {
  locomotionPacing = true,
  position = { cellX = 1, cellY = 1 },
  mapId = semantics.mapId,
  worldSemantics = semantics,
  occupiedCells = {}, occupancyDetails = {}, targetPositions = {}
}, 1)
assertEquals(needActor.runtimeState.movementRequest
  and needActor.runtimeState.movementRequest.traversalMode, "WALK",
  "SATISFY_NEED should execute its retained goal under production pacing")

local settled = {
  id = "stable-settled",
  temperament = { curiosity = 0.5, sociability = 0.5, boldness = 0.5 },
  rawStats = { independence = 0.5 },
  runtimeState = { state = "SETTLED", stateEnteredTick = 0 }
}
for tick = 1, 180 do
  local state = Controller.tick(settled, {}, nil, {
    hasTarget = false, purposefulTarget = false,
    position = { cellX = 5, cellY = 5 }, targetPositions = {},
    allowTargeting = true
  }, tick)
  assertEquals(state, "SETTLED",
    "no unmet motivation should leave passive equilibrium")
  assertEquals(settled.runtimeState.movementRequest, nil,
    "passive equilibrium should emit no movement request")
  assertEquals(settled.runtimeState.navigation, nil,
    "passive equilibrium should own no navigation episode")
end

local canFlee, fleeReason = LocomotionPolicy.decide(
  actorFor("FLEE"), "FLEE", { locomotionPacing = true }, 1, false)
assertEquals(canFlee, true, "FLEE must bypass ordinary locomotion style")
assertEquals(fleeReason, "FLEE_URGENCY",
  "FLEE bypass should retain explicit urgency provenance")

local fleeing = Controller.tick(settled, {}, 1, {
  hasTarget = true, purposefulTarget = true,
  position = { cellX = 5, cellY = 5 },
  targetPositions = { threat = { cellX = 5, cellY = 6 } },
  threatAssessment = {
    primaryThreatId = "threat",
    primaryThreatReason = "HIGH_SEVERITY_EVENT",
    primaryThreatScore = 200,
    primaryThreatDistance = 1,
    primaryThreatSevere = true
  },
  currentFear = 0.9
}, 181)
assertEquals(fleeing, "FLEE",
  "severe threat should interrupt SETTLED immediately")

print("LOCOMOTION_HOMEOSTASIS coherentSteps=32 pacedNeed=true settledTicks=180 fleeImmediate=true")

return true