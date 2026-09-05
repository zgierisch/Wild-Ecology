local Controller = require("src.behavior.controller")
local Utility = require("src.behavior.utility")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function fleeContext(position, threatPosition, severe)
  return {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = "player",
    threatAssessment = {
      primaryThreatId = "player",
      primaryThreatScore = severe and 200 or 40,
      primaryThreatReason = severe and "HIGH_SEVERITY_EVENT" or "HOSTILITY",
      primaryThreatDistance = math.max(
        math.abs(position.cellX - threatPosition.cellX),
        math.abs(position.cellY - threatPosition.cellY)),
      primaryThreatSevere = severe == true
    },
    currentFear = severe and 0.9 or 0.6,
    position = position,
    targetPositions = { player = threatPosition },
    goalRadius = 1,
    fleeRadius = 4,
    fleeSafetyDistance = 7
  }
end

assertEquals(Controller.reconsiderationReason({}, 1, nil, true), "INITIAL",
  "an actor without a prior decision should deliberate")
assertEquals(Controller.reconsiderationReason({
  state = "IDLE",
  threatAssessment = {
    primaryThreatId = "player",
    primaryThreatReason = "HIGH_SEVERITY_EVENT",
    primaryThreatDistance = 1,
    primaryThreatSevere = true
  }
}, 1, nil, true), "INITIAL",
  "route entry should combine a newly severe threat with its one INITIAL deliberation")
assertEquals(Controller.reconsiderationReason({
  state = "IDLE",
  fearCurrent = 0.9,
  threatAssessment = {
    primaryThreatId = "player",
    primaryThreatReason = "HOSTILITY",
    primaryThreatDistance = 1,
    primaryThreatSevere = false
  }
}, 1, nil, true), "INITIAL",
  "route entry should combine already-urgent Fear with its one INITIAL deliberation")
local reasonRuntime = {
  state = "APPROACH",
  lastDecisionTick = 10,
  nextDecisionTick = 25,
  lastSchedulerDebugPreset = nil,
  intentEpisode = { intent = "APPROACH", status = "ACTIVE" }
}
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), nil,
  "an active valid episode should not deliberate before cadence")
assertEquals(Controller.reconsiderationReason(reasonRuntime, 25, nil, true), "CADENCE",
  "the existing 15-tick cadence should request deliberation")
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, "APPROACH", true),
  "DEBUG_PRESET_CHANGED", "a preset change should request one immediate deliberation")
reasonRuntime.lastSchedulerDebugPreset = "APPROACH"
assertEquals(Controller.reconsiderationReason(reasonRuntime, 21, "APPROACH", true), nil,
  "an unchanged preset should return to normal cadence")
reasonRuntime.lastSchedulerDebugPreset = nil
reasonRuntime.threatAssessment = {
  primaryThreatId = "player",
  primaryThreatReason = "HIGH_SEVERITY_EVENT",
  primaryThreatDistance = 1,
  primaryThreatSevere = true
}
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), "SEVERE_EVENT",
  "severe danger should interrupt an ordinary intent immediately")
reasonRuntime.state = "FLEE"
reasonRuntime.intentEpisode = { intent = "FLEE", status = "ACTIVE" }
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), nil,
  "sustained severe danger must not repeatedly deliberate an active FLEE")
for sustainedTick = 21, 24 do
  assertEquals(Controller.reconsiderationReason(
    reasonRuntime, sustainedTick, nil, true), nil,
    "the same sustained danger must remain execution-only while FLEE is active")
end
assertEquals(Controller.reconsiderationReason(
  reasonRuntime, 25, nil, true), "CADENCE",
  "active FLEE should retain its scheduled high-level cadence")
reasonRuntime.state = "APPROACH"
reasonRuntime.threatAssessment = nil
reasonRuntime.intentEpisode = { intent = "APPROACH", status = "SATISFIED" }
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), "INTENT_SATISFIED",
  "terminal satisfaction should request immediate deliberation")
reasonRuntime.intentEpisode.status = "FAILED"
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), "INTENT_FAILED",
  "terminal failure should request immediate deliberation")
reasonRuntime.intentEpisode.status = "INVALIDATED"
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, true), "INTENT_INVALIDATED",
  "terminal invalidation should request immediate deliberation")
reasonRuntime.intentEpisode.status = "ACTIVE"
reasonRuntime.targetEntityId = "friend"
assertEquals(Controller.reconsiderationReason(reasonRuntime, 20, nil, false), "TARGET_INVALIDATED",
  "removed current targets should request immediate deliberation")

local threatPosition = { cellX = 0, cellY = 0 }
local fleePosition = { cellX = 0, cellY = 2 }
local fleer = {
  id = "scheduler-fleer",
  temperament = { boldness = 0, curiosity = 0 },
  relationships = { player = { hostility = 40 } },
  runtimeState = { directThreatId = "player", fearCurrent = 0.9, fearDirect = 0.9 }
}
local scoreRunsBefore = Utility.getBehaviorScoreRunCount()
assertEquals(Controller.tick(fleer, fleer.relationships.player, 2,
  fleeContext(fleePosition, threatPosition, true), 0), "FLEE",
  "fixture should begin in active FLEE")
fleer.runtimeState.lastDecisionTick = 0
fleer.runtimeState.nextDecisionTick = 15
fleer.runtimeState.lastSchedulerDebugPreset = nil
local deliberations = 1
local movementRequests = fleer.runtimeState.movementRequest and 1 or 0
local executionUpdates = 0

for tick = 1, 30 do
  local request = fleer.runtimeState.movementRequest
  if request and request.destinationX ~= nil and request.destinationY ~= nil then
    fleePosition = { cellX = request.destinationX, cellY = request.destinationY }
    fleer.runtimeState.motion = { justCompleted = true }
  else
    fleer.runtimeState.motion = { active = false }
  end
  local reason = Controller.reconsiderationReason(
    fleer.runtimeState, tick, nil, true)
  if reason then
    Controller.tick(fleer, fleer.relationships.player,
      math.max(math.abs(fleePosition.cellX), math.abs(fleePosition.cellY)),
      fleeContext(fleePosition, threatPosition, false), tick)
    fleer.runtimeState.lastDecisionTick = tick
    fleer.runtimeState.nextDecisionTick = tick + 15
    deliberations = deliberations + 1
  else
    local context = fleeContext(fleePosition, threatPosition, false)
    context.executionOnly = true
    context.executionUpdateReason = "MOVEMENT_COMPLETED"
    Controller.executeCurrentIntent(fleer, context, tick)
    executionUpdates = executionUpdates + 1
  end
  if fleer.runtimeState.movementRequest
    and fleer.runtimeState.movementRequest.issuedTick == tick then
    movementRequests = movementRequests + 1
  end
end

local scoreRunsAfter = Utility.getBehaviorScoreRunCount()
assertEquals(deliberations, 3,
  "31 lifecycle samples should deliberate only initially and at ticks 15/30")
assertEquals(scoreRunsAfter - scoreRunsBefore, 3,
  "execution-only FLEE updates must not evaluate the utility table")
assertEquals(executionUpdates, 28,
  "non-deliberation lifecycle samples should update current-intent execution")
assertTrue(movementRequests >= 25,
  "completed FLEE WALKs should receive prompt replacement actions")
assertEquals(fleer.runtimeState.state, "FLEE",
  "responsive execution must retain the active FLEE purpose")

local approacher = {
  id = "scheduler-approacher",
  temperament = { curiosity = 0.1, sociability = 0.8 },
  rawStats = { independence = 0.2 },
  runtimeState = {
    state = "APPROACH",
    stateEnteredTick = 0,
    lastDecisionTick = 0,
    nextDecisionTick = 15,
    targetEntityId = "friend"
  }
}
local approachContext = {
  hasTarget = true,
  purposefulTarget = true,
  targetEntityId = "friend",
  position = { cellX = 0, cellY = 0 },
  targetPositions = { friend = { cellX = 1, cellY = 0 } },
  goalRadius = 1
}
Controller.executeCurrentIntent(approacher, approachContext, 5)
assertEquals(approacher.runtimeState.intentEpisode.status, "SATISFIED",
  "execution should detect purpose satisfaction before cadence")
assertEquals(Controller.reconsiderationReason(approacher.runtimeState, 5, nil, true),
  "INTENT_SATISFIED", "satisfaction should immediately request high-level reconsideration")

local seeker = {
  id = "scheduler-blocked-seeker",
  species = "PIDGEY",
  temperament = { sociability = 0.9 },
  rawStats = { independence = 0.1 },
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 0,
    lastDecisionTick = 0,
    nextDecisionTick = 15,
    targetEntityId = "peer"
  }
}
local seekContext = {
  position = { cellX = 0, cellY = 0 },
  flockSearch = {
    utility = 60,
    nearbySameSpecies = 0,
    cueSource = "perceived",
    cuePosition = { cellX = 5, cellY = 0 },
    targetEntityId = "peer"
  }
}
Controller.executeCurrentIntent(seeker, seekContext, 1)
for attempt = 1, 3 do
  seeker.runtimeState.movementRequest = {
    direction = "RIGHT",
    issuedTick = attempt,
    rejectionReason = "tile"
  }
  Controller.executeCurrentIntent(seeker, seekContext, attempt + 1)
  local expected = attempt < 3 and "ACTIVE" or "FAILED"
  assertEquals(seeker.runtimeState.intentEpisode.status, expected,
    "only three distinct rejected WALK attempts should fail the intent")
  if attempt == 1 then
    Controller.executeCurrentIntent(seeker, seekContext, attempt + 1)
    assertEquals(seeker.runtimeState.intentEpisode.failedAttempts, 1,
      "polling one rejected WALK repeatedly must not multiply failures")
  end
end
assertEquals(Controller.reconsiderationReason(seeker.runtimeState, 5, nil, true),
  "INTENT_FAILED", "navigation failure should deliberate only at intent failure")

print(string.format(
  "SCHEDULER lifecycle=31 deliberations=%d deliberationsPer100=%.2f utilityEvaluations=%d movementRequests=%d executionUpdates=%d",
  deliberations, deliberations * 100 / 31, scoreRunsAfter - scoreRunsBefore,
  movementRequests, executionUpdates))

return true
