local Controller = require("src.behavior.controller")
local FlockSearch = require("src.behavior.flock_search")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local liveEquivalent = {
  id = "wild:route02:0039-equivalent",
  species = "PIDGEY",
  ecology = { family = "family-a", socialModifier = 1, desiredGroupSize = 4 },
  temperament = { sociability = 0.9, boldness = 0.15, curiosity = 0 },
  rawStats = { independence = 0.1 },
  relationships = {},
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 0,
    lastFleeEndTick = 100,
    directThreatId = "player",
    fearCurrent = 0.29,
    fearDirect = 0.29,
    fearSocial = 0,
    escapeUrgency = 0.27,
    flockSearch = {
      sightings = {},
      signals = {},
      isolationSinceTick = 0,
      familySeparatedSinceTick = 0
    }
  }
}
local position = { cellX = 2, cellY = 2 }
local search = FlockSearch.update(liveEquivalent, position, {}, 400)
assertEquals(search.reassemblyPressure, 0,
  "renewed authoritative danger must suspend post-FLEE reassembly pressure")
assertEquals(search.activeAlarm, true, "current direct threat should mark the social context unsafe")

local threat = {
  primaryThreatId = "player",
  primaryThreatReason = "TRAINER_WARINESS",
  primaryThreatScore = 28,
  primaryThreatDistance = 2,
  primaryThreatSevere = false
}
local context = {
  position = position,
  targetPositions = { player = { cellX = 2, cellY = 4 } },
  threatAssessment = threat,
  currentFear = 0.29,
  flockSearch = search
}
local moderate = Controller.tick(liveEquivalent, {}, 2, context, 400)
assertEquals(moderate, "SEEK_FLOCK",
  "live-equivalent moderate safety pressure may retain a strongly committed reunion episode")
assertTrue(liveEquivalent.runtimeState.behaviorScores.SEEK_FLOCK
    > liveEquivalent.runtimeState.behaviorScores.FLEE,
  "at fear 0.29 SEEK_FLOCK should still be the raw utility winner")
local moderateFlee = liveEquivalent.runtimeState.behaviorScores.FLEE
local moderateSeek = liveEquivalent.runtimeState.behaviorScores.SEEK_FLOCK

context.currentFear = 0.6
liveEquivalent.runtimeState.fearCurrent = 0.6
liveEquivalent.runtimeState.fearDirect = 0.6
local safetyWins = Controller.tick(liveEquivalent, {}, 2, context, 430)
assertEquals(safetyWins, "FLEE",
  "integrated safety utility should eventually displace reunion seeking before emergency override")
assertEquals(liveEquivalent.runtimeState.emergencyFlee, false,
  "moderate/high ordinary fear crossover must not use emergency state assignment")
assertEquals(liveEquivalent.runtimeState.candidateWinner, "FLEE",
  "FLEE should win the raw utility crossover")
assertTrue(liveEquivalent.runtimeState.behaviorScores.FLEE
    > liveEquivalent.runtimeState.behaviorScores.SEEK_FLOCK
      + liveEquivalent.runtimeState.intentSwitchMargin,
  "safety must meaningfully exceed the active social episode commitment")

local socialActor = {
  id = "long-run-approacher",
  species = "PIDGEY",
  temperament = { curiosity = 0, sociability = 0.9, boldness = 0.7 },
  rawStats = { independence = 0.15 },
  runtimeState = {}
}
local relationship = { trust = 70, affinity = 55, familiarity = 100 }
local actorPosition = { cellX = 0, cellY = 0 }
local targetPosition = { cellX = 4, cellY = 0 }
local movementDecisions = 0
local behaviorDecisions = 0
local approachTargetTransitions = 0
local previousState = nil
local immediateReacquisition = false
local satisfactionTick = nil

for tick = 0, 360, 15 do
  behaviorDecisions = behaviorDecisions + 1
  if socialActor.runtimeState.motion and socialActor.runtimeState.motion.active then
    socialActor.runtimeState.motion.active = false
    socialActor.runtimeState.motion.justCompleted = true
  end
  local distance = math.max(
    math.abs(actorPosition.cellX - targetPosition.cellX),
    math.abs(actorPosition.cellY - targetPosition.cellY))
  local state = Controller.tick(socialActor, relationship, distance, {
    hasTarget = true,
    purposefulTarget = true,
    conspecific = true,
    targetEntityId = "friend",
    candidates = { { id = "friend", distance = distance, novelty = 0 } },
    position = actorPosition,
    targetPositions = { friend = targetPosition },
    goalRadius = 1
  }, tick)
  local request = socialActor.runtimeState.movementRequest
  if request and request.traversalMode == "WALK" then
    movementDecisions = movementDecisions + 1
    actorPosition = { cellX = request.destinationX, cellY = request.destinationY }
    socialActor.runtimeState.motion = { active = true }
  end
  if (previousState == "APPROACH" and state == "TARGET")
    or (previousState == "TARGET" and state == "APPROACH") then
    approachTargetTransitions = approachTargetTransitions + 1
  end
  if socialActor.runtimeState.recentSatisfactionTick and not satisfactionTick then
    satisfactionTick = socialActor.runtimeState.recentSatisfactionTick
  end
  if satisfactionTick and tick - satisfactionTick <= 60 and state == "APPROACH" then
    immediateReacquisition = true
  end
  previousState = state
end

local metrics = socialActor.runtimeState.intentMetrics or {}
assertTrue(movementDecisions > 3, "long-run NORMAL actor should remain active")
assertEquals(immediateReacquisition, false,
  "satisfied APPROACH must not immediately reacquire the same target")
assertTrue((metrics.intentSwitches or 0) < behaviorDecisions,
  "intent switches should be less frequent than normal behavior decisions")
assertEquals(approachTargetTransitions, 0,
  "long-run social behavior must not settle into periodic APPROACH/TARGET thrashing")
assertTrue((metrics.purposefulIntentCompletions or 0) >= 1,
  "long-run simulation should record purposeful completion")

print(string.format(
  "0039_EQUIVALENT fear=.29 FLEE=%.2f SEEK_FLOCK=%.2f; fear=.60 FLEE=%.2f SEEK_FLOCK=%.2f margin=%.2f",
  moderateFlee, moderateSeek,
  liveEquivalent.runtimeState.behaviorScores.FLEE,
  liveEquivalent.runtimeState.behaviorScores.SEEK_FLOCK,
  liveEquivalent.runtimeState.intentSwitchMargin or 0))
print(string.format(
  "LONG_RUN decisions=%d movement=%d switches=%d switchesPer100Ticks=%.2f completions=%d interruptions=%d approachTargetTransitions=%d",
  behaviorDecisions, movementDecisions, metrics.intentSwitches or 0,
  (metrics.intentSwitches or 0) * 100 / 360,
  metrics.purposefulIntentCompletions or 0,
  metrics.purposefulIntentInterruptions or 0,
  approachTargetTransitions))

return true
