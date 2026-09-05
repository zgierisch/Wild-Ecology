local Controller = require("src.behavior.controller")
local IntentEpisode = require("src.behavior.intent_episode")
local NavigationGoal = require("src.navigation.navigation_goal")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function approachContext(targetId, actorX, targetX)
  return {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = targetId,
    conspecific = true,
    candidates = { { id = targetId, distance = math.abs(targetX - actorX), novelty = 0 } },
    position = { cellX = actorX, cellY = 0 },
    targetPositions = { [targetId] = { cellX = targetX, cellY = 0 } },
    goalRadius = 1,
    allowTargeting = true
  }
end

local relationship = { trust = 35, affinity = 0, familiarity = 100 }
local approacher = {
  id = "episode-approacher",
  temperament = { curiosity = 0, sociability = 0.8 },
  rawStats = { independence = 0.2 },
  runtimeState = { state = "APPROACH", stateEnteredTick = 0 }
}
local targetId = "friend-b"
local continuing = Controller.tick(approacher, relationship, 4, approachContext(targetId, 1, 5), 40)
assertEquals(continuing, "APPROACH", "a valid progressing APPROACH should survive a marginal ordinary challenger")
assertEquals(approacher.runtimeState.intentEpisode.status, "ACTIVE", "purposeful intent should create an active episode")
assertEquals(approacher.runtimeState.intentEpisode.targetId, targetId, "episode should own the purposeful target")

local progressed = Controller.tick(approacher, relationship, 3, approachContext(targetId, 2, 5), 55)
assertEquals(progressed, "APPROACH", "distance progress should retain APPROACH")
assertTrue(approacher.runtimeState.intentEpisode.progress > 0, "distance reduction should record intent progress")

local satisfied = Controller.tick(approacher, relationship, 1, approachContext(targetId, 4, 5), 70)
assertEquals(satisfied, "SETTLED", "satisfied APPROACH should enter passive equilibrium")
assertEquals(approacher.runtimeState.intentEpisode.status, "SATISFIED", "reaching preferred proximity should satisfy the episode")
assertEquals(approacher.runtimeState.recentSatisfiedIntent, "APPROACH", "satisfaction memory should name the completed intent")
assertEquals(approacher.runtimeState.recentSatisfiedTarget, targetId, "satisfaction memory should be target-specific")

local dwell = Controller.tick(approacher, relationship, 1, approachContext(targetId, 4, 5), 85)
assertEquals(dwell, "SETTLED", "ambient TARGET must not immediately undo a satisfied social goal")
assertTrue((approacher.runtimeState.behaviorScores.APPROACH or 0) < (approacher.runtimeState.behaviorScores.IDLE or 0),
  "same-target APPROACH reacquisition should be temporarily suppressed")

relationship.trust = 70
relationship.affinity = 50
local movedAway = Controller.tick(approacher, relationship, 4, approachContext(targetId, 1, 5), 100)
assertEquals(movedAway, "APPROACH", "meaningful target separation should release same-target satisfaction suppression")

local severeContext = approachContext(targetId, 4, 5)
severeContext.threatAssessment = {
  primaryThreatId = "player",
  primaryThreatReason = "HIGH_SEVERITY_EVENT",
  primaryThreatScore = 200,
  primaryThreatDistance = 1,
  primaryThreatSevere = true
}
severeContext.targetPositions.player = { cellX = 4, cellY = 1 }
severeContext.currentFear = 0.9
local interrupted = Controller.tick(approacher, { hostility = 20 }, 1, severeContext, 101)
assertEquals(interrupted, "FLEE", "severe danger must immediately interrupt social dwell")
assertEquals(approacher.runtimeState.intentEpisode.status, "ACTIVE", "FLEE should begin its own active episode")
assertEquals(approacher.runtimeState.lastIntentEpisodeOutcome, "INTERRUPTED", "the prior ordinary episode should record emergency interruption")

approacher.runtimeState.targetEntityId = "unrelated-wild"
IntentEpisode.observe(approacher, "FLEE", "unrelated-wild", nil, {
  position = { cellX = 4, cellY = 1 },
  targetPositions = { ["unrelated-wild"] = { cellX = 5, cellY = 1 } }
}, 102, false)
assertEquals(approacher.runtimeState.intentEpisode.targetId, nil,
  "active FLEE must clear episode target identity when authoritative threat identity disappears")

local seeker = {
  id = "episode-seeker",
  species = "PIDGEY",
  ecology = { family = "a" },
  temperament = { curiosity = 0, sociability = 0.9 },
  rawStats = { independence = 0.1 },
  runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 0 }
}
local function seekContext(target, actorX, targetX, utility)
  return {
    hasTarget = false,
    position = { cellX = actorX, cellY = 0 },
    flockSearch = {
      utility = utility,
      isolationPressure = 1,
      groupDeficit = 1,
      nearbySameSpecies = 0,
      cueSource = "perceived",
      cuePosition = { cellX = targetX, cellY = 0 },
      targetEntityId = target
    }
  }
end

assertEquals(Controller.tick(seeker, {}, nil, seekContext("peer-a", 0, 6, 60), 40), "SEEK_FLOCK",
  "strong social purpose should remain SEEK_FLOCK")
assertEquals(Controller.tick(seeker, {}, nil, seekContext("peer-a", 1, 6, 12), 55), "SEEK_FLOCK",
  "progressing SEEK_FLOCK should survive a modest score dip")
local startsBeforeRetarget = seeker.runtimeState.intentMetrics.purposefulIntentStarts
assertEquals(Controller.tick(seeker, {}, nil, seekContext("peer-b", 2, 5, 12), 70), "SEEK_FLOCK",
  "SEEK_FLOCK should retain its high-level intent while substituting a valid peer")
assertEquals(seeker.runtimeState.intentEpisode.targetId, "peer-b", "retarget should update the episode target")
assertEquals(seeker.runtimeState.intentMetrics.purposefulIntentStarts, startsBeforeRetarget,
  "retargeting within SEEK_FLOCK must not count as a new intent start")

local blocked = {
  id = "blocked-seeker",
  species = "PIDGEY",
  temperament = { curiosity = 0, sociability = 0.9 },
  rawStats = { independence = 0.1 },
  runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 0 }
}
local blockedContext = seekContext("blocked-peer", 0, 6, 60)
for tick = 40, 42 do
  blocked.runtimeState.movementRequest = {
    direction = "UP", destinationX = 0, destinationY = -1,
    rejectionReason = "tile"
  }
  Controller.tick(blocked, {}, nil, blockedContext, tick)
end
assertEquals(blocked.runtimeState.lastIntentEpisodeOutcome, "FAILED",
  "repeated inability to execute movement should fail the purposeful episode")
assertTrue(blocked.runtimeState.state ~= "SEEK_FLOCK",
  "failed SEEK_FLOCK must release control instead of restarting immediately")

local perceivedGoal = NavigationGoal.fromFlockSearch({
  cueSource = "perceived",
  cuePosition = { cellX = 5, cellY = 2 },
  targetEntityId = "visible-peer"
})
assertEquals(perceivedGoal.kind, "PROXIMITY", "currently perceived peers should create proximity navigation goals")
assertEquals(perceivedGoal.destination.cellX, 5, "perceived goal should use the legitimate observed position")

return true
