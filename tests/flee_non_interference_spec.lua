local Controller = require("src.behavior.controller")
local MovementClaims = require("src.world.movement_claims")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local actor = {
  id = "flee-non-interference-seeker",
  species = "PIDGEY",
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 0.9, boldness = 0 },
  rawStats = { independence = 0.1 },
  relationships = {},
  runtimeState = {
    state = "SEEK_FLOCK",
    stateEnteredTick = 1,
    motion = { active = false },
    navigation = {
      goalSignature = "ordinary-flock-route",
      route = { index = 1, actions = { { direction = "RIGHT" } } }
    },
    movementRequest = {
      direction = "RIGHT",
      traversalMode = "WALK",
      sourceX = 4,
      sourceY = 4,
      destinationX = 5,
      destinationY = 4,
      goalKind = "SEEK_FLOCK"
    }
  }
}

local state = Controller.tick(actor, { hostility = 100 }, 1, {
  hasTarget = true,
  purposefulTarget = true,
  targetEntityId = "threat",
  threatAssessment = {
    primaryThreatId = "threat",
    primaryThreatScore = 200,
    primaryThreatReason = "HIGH_SEVERITY_EVENT",
    primaryThreatDistance = 1,
    primaryThreatSevere = true
  },
  currentFear = 0.9,
  position = { cellX = 4, cellY = 4 },
  targetPositions = { threat = { cellX = 4, cellY = 3 } },
  occupiedCells = { ["4,3"] = true },
  mapId = "FLEE_OWNERSHIP"
}, 2)

assertEquals(state, "FLEE", "severe danger should interrupt SEEK_FLOCK")
assertEquals(actor.runtimeState.navigation, nil,
  "entering FLEE must release the prior ordinary navigation route")
assertEquals(actor.runtimeState.movementRequest.goalKind == "SEEK_FLOCK", false,
  "FLEE must replace the prior ordinary movement request")
assertEquals(actor.runtimeState.movementRequest.targetEntityId, "threat",
  "the replacement request should belong to the authoritative threat")

local relationship = {
  familiarity = 40,
  trust = 15,
  affinity = 5,
  threatMemory = 70,
  directThreatMemory = 70,
  hostility = 10
}
local recovering = {
  id = "flee-non-interference-recovery",
  species = "PIDGEY",
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 0.5, boldness = 0 },
  rawStats = { independence = 0.5 },
  relationships = { threat = relationship },
  runtimeState = {
    state = "FLEE",
    stateEnteredTick = 1,
    fearCurrent = 0,
    fearDirect = 0,
    fearSocial = 0,
    fleeSafeTicks = 29,
    fleeExecution = {
      escapeMode = true,
      route = { index = 2, actions = { { direction = "LEFT" } } }
    },
    escapeHeading = { dx = 1, dy = 0, residualX = 0.5, residualY = 0 },
    escapeSeparationMomentum = { dx = 0.25, dy = 0 },
    escapeReference = { kind = "LAST_KNOWN_THREAT_POSITION" },
    fleeThreatPosition = { cellX = 3, cellY = 4 },
    fleeThreatPositionTick = 1,
    fleeThreatEntityId = "threat",
    recentCommittedCells = {
      { key = "4,4", threatId = "threat" },
      { key = "5,4", threatId = "threat" }
    },
    rejectedMoves = {
      LEFT = { mapId = "FLEE_OWNERSHIP", cellX = 5, cellY = 4, reason = "tile" }
    },
    socialEscapeBias = { dx = 1, dy = 0 },
    socialEscapeBiasConfidence = 0.4,
    motion = { active = false }
  }
}

local recoveredState = Controller.tick(recovering, {}, nil, {
  hasTarget = false,
  purposefulTarget = false,
  allowTargeting = false,
  threatAssessment = { primaryThreatId = nil },
  currentFear = 0,
  position = { cellX = 8, cellY = 8 },
  targetPositions = {},
  mapId = "FLEE_OWNERSHIP"
}, 31)

assertEquals(recoveredState, "SETTLED", "sustained safety should release FLEE into equilibrium")
assertEquals(recovering.runtimeState.fleeExecution, nil,
  "FLEE exit must release its route and planner state")
assertEquals(recovering.runtimeState.escapeHeading, nil,
  "FLEE exit must release heading inertia")
assertEquals(recovering.runtimeState.escapeSeparationMomentum, nil,
  "FLEE exit must release separation momentum")
assertEquals(recovering.runtimeState.escapeReference, nil,
  "FLEE exit must release threat geometry")
assertEquals(recovering.runtimeState.fleeThreatPosition, nil,
  "FLEE exit must release the last-known threat position")
assertEquals(recovering.runtimeState.targetEntityId, nil,
  "IDLE must not inherit FLEE threat ownership")
assertEquals(recovering.runtimeState.movementRequest, nil,
  "IDLE must not inherit a FLEE movement request")
assertEquals(#recovering.runtimeState.recentCommittedCells, 0,
  "FLEE exit must release route-cycle history before ordinary navigation")
assertEquals(recovering.runtimeState.rejectedMoves.LEFT.reason, "tile",
  "generic map-local collision knowledge should survive a behavior transition")
assertEquals(recovering.runtimeState.socialEscapeBias.dx, 1,
  "Fear-owned social evidence should decay through Fear rather than FLEE cleanup")
assertEquals(recovering.relationships.threat, relationship,
  "transient FLEE cleanup must preserve the persistent relationship record")
assertEquals(recovering.relationships.threat.threatMemory, 70,
  "transient FLEE cleanup must preserve durable threat memory")

local function severeContext(threatId, actorX)
  return {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = threatId,
    threatAssessment = {
      primaryThreatId = threatId,
      primaryThreatScore = 200,
      primaryThreatReason = "HIGH_SEVERITY_EVENT",
      primaryThreatDistance = 1,
      primaryThreatSevere = true
    },
    currentFear = 0.9,
    position = { cellX = actorX or 4, cellY = 4 },
    targetPositions = { [threatId] = { cellX = actorX or 4, cellY = 3 } },
    occupiedCells = { [(actorX or 4) .. ",3"] = true },
    mapId = "FLEE_OWNERSHIP"
  }
end

for _, priorState in ipairs({
  "APPROACH", "INVESTIGATE", "SEEK_FLOCK", "TARGET", "SETTLED", "IDLE", "REST"
}) do
  local priorRelationship = { trust = 27, affinity = 19, threatMemory = 11 }
  local matrixActor = {
    id = "flee-entry-" .. string.lower(priorState),
    species = "PIDGEY",
    ecology = { family = "flock-a", locomotion = { WALK = true } },
    temperament = { curiosity = 0.5, sociability = 0.5, boldness = 0 },
    rawStats = { independence = 0.5 },
    relationships = { threat = priorRelationship },
    runtimeState = {
      state = priorState,
      stateEnteredTick = 1,
      targetEntityId = priorState == "TARGET" and nil or "ordinary-target",
      targetDestination = priorState == "TARGET"
        and { id = "target_right", cellX = 7, cellY = 4 } or nil,
      flockSearchDestination = priorState == "SEEK_FLOCK"
        and { cellX = 7, cellY = 4 } or nil,
      navigation = priorState == "SEEK_FLOCK" and {
        route = { index = 1, actions = { { direction = "RIGHT" } } }
      } or nil,
      movementRequest = {
        direction = "RIGHT", traversalMode = "WALK",
        sourceX = 4, sourceY = 4, destinationX = 5, destinationY = 4,
        goalKind = priorState
      },
      motion = { active = false }
    }
  }
  local matrixState = Controller.tick(matrixActor, { hostility = 100 }, 1,
    severeContext("threat", 4), 2)
  assertEquals(matrixState, "FLEE",
    priorState .. " should yield immediately to severe danger")
  assertEquals(matrixActor.relationships.threat, priorRelationship,
    priorState .. " interruption must preserve relationship identity")
  assertEquals(matrixActor.runtimeState.targetEntityId, "threat",
    priorState .. " interruption must transfer target ownership to the threat")
  assertEquals(matrixActor.runtimeState.movementRequest.goalKind == priorState, false,
    priorState .. " interruption must replace its queued movement request")
  assertEquals(matrixActor.runtimeState.intentEpisode.intent, "FLEE",
    priorState .. " interruption must establish a FLEE intent episode")
  if priorState == "SEEK_FLOCK" then
    assertEquals(matrixActor.runtimeState.navigation, nil,
      "SEEK_FLOCK interruption must release its ordinary route")
  end
end

local claims = MovementClaims.new()
local claimActor = {
  id = "flee-claim-cleanup",
  temperament = { curiosity = 0, sociability = 0, boldness = 0 },
  runtimeState = {
    state = "FLEE",
    stateEnteredTick = 1,
    fearCurrent = 0,
    fearDirect = 0,
    fearSocial = 0,
    fleeSafeTicks = 29,
    targetEntityId = "threat",
    movementRequest = {
      direction = "RIGHT", traversalMode = "WALK",
      sourceX = 4, sourceY = 4, destinationX = 5, destinationY = 4
    },
    motion = { active = false }
  }
}
assertEquals(claims:publish({
  actorId = claimActor.id, fromX = 4, fromY = 4, toX = 5, toY = 4,
  intent = "FLEE", urgency = 0.9
}, 30), true, "active FLEE should be able to own a movement claim")
Controller.tick(claimActor, {}, nil, {
  hasTarget = false,
  allowTargeting = false,
  threatAssessment = { primaryThreatId = nil },
  currentFear = 0,
  position = { cellX = 4, cellY = 4 },
  targetPositions = {}
}, 31)
claims:validateActor(claimActor.id, claimActor.runtimeState,
  { cellX = 4, cellY = 4 }, 31)
assertEquals(claims:claimForActor(claimActor.id), nil,
  "the claim registry must release a canceled FLEE request after exit")

local repeatedRelationship = { trust = 9, affinity = 6, threatMemory = 44 }
local repeated = {
  id = "repeated-flee-episodes",
  species = "PIDGEY",
  personalitySeed = 77,
  ecology = { family = "flock-a", locomotion = { WALK = true } },
  temperament = { curiosity = 0, sociability = 0.5, boldness = 0 },
  rawStats = { independence = 0.5 },
  relationships = { trainer = repeatedRelationship, wild = repeatedRelationship },
  runtimeState = { state = "IDLE", stateEnteredTick = 0, motion = { active = false } }
}
for episode = 1, 50 do
  local threatId = episode % 2 == 0 and "trainer" or "wild"
  local entryTick = episode * 3
  assertEquals(Controller.tick(repeated, { hostility = 100 }, 1,
    severeContext(threatId, 4), entryTick), "FLEE",
    "repeated episode should enter FLEE with the current generic threat")
  assertEquals(repeated.runtimeState.targetEntityId, threatId,
    "repeated episode must not retain the prior threat identity")
  repeated.runtimeState.fearCurrent = 0
  repeated.runtimeState.fearDirect = 0
  repeated.runtimeState.fearSocial = 0
  repeated.runtimeState.fleeSafeTicks = 29
  repeated.runtimeState.movementRequest = {
    direction = "STAY", traversalMode = "NONE", reason = "NO_ESCAPE_ROUTE"
  }
  local exitState = Controller.tick(repeated, {}, nil, {
    hasTarget = false,
    purposefulTarget = false,
    allowTargeting = false,
    threatAssessment = { primaryThreatId = nil },
    currentFear = 0,
    position = { cellX = 4, cellY = 4 },
    targetPositions = {}
  }, entryTick + 1)
  assertEquals(exitState, "SETTLED",
    "trapped STAY history must not prevent safe FLEE recovery")
  assertEquals(repeated.runtimeState.targetEntityId, nil,
    "repeated exit must release threat target ownership")
  assertEquals(repeated.runtimeState.fleeExecution, nil,
    "repeated exit must release planner ownership")
  assertEquals(repeated.runtimeState.movementRequest, nil,
    "repeated exit must release STAY or WALK request ownership")
  assertEquals(#(repeated.runtimeState.recentCommittedCells or {}), 0,
    "repeated exit must leave ordinary route-cycle history empty")
end
assertEquals(repeated.relationships.trainer, repeatedRelationship,
  "repeated trainer FLEE must preserve persistent relationships")
assertEquals(repeated.relationships.wild, repeatedRelationship,
  "repeated wild FLEE must use the same generic relationship ownership")

local mixed = {
  id = "mixed-flee-simulation",
  temperament = { curiosity = 0, sociability = 0, boldness = 0 },
  runtimeState = { state = "IDLE", stateEnteredTick = 0, motion = { active = false } }
}
local fleeEntries, fleeExits = 0, 0
for tick = 1, 1000 do
  local cycle = (tick - 1) % 100
  if cycle == 0 then
    Controller.tick(mixed, { hostility = 100 }, 1,
      severeContext(cycle % 200 == 0 and "trainer" or "wild", 4), tick)
    fleeEntries = fleeEntries + (mixed.runtimeState.state == "FLEE" and 1 or 0)
  elseif cycle == 31 then
    mixed.runtimeState.fearCurrent = 0
    mixed.runtimeState.fearDirect = 0
    mixed.runtimeState.fearSocial = 0
    mixed.runtimeState.fleeSafeTicks = 29
    Controller.tick(mixed, {}, nil, {
      hasTarget = false, allowTargeting = false,
      threatAssessment = { primaryThreatId = nil }, currentFear = 0,
      position = { cellX = 4, cellY = 4 }, targetPositions = {}
    }, tick)
    fleeExits = fleeExits + (mixed.runtimeState.state ~= "FLEE" and 1 or 0)
  elseif mixed.runtimeState.state == "FLEE" then
    Controller.executeCurrentIntent(mixed, {
      executionOnly = true,
      threatAssessment = { primaryThreatId = "trainer" },
      currentFear = 0.9,
      position = { cellX = 4, cellY = 4 },
      targetPositions = { trainer = { cellX = 4, cellY = 3 } }
    }, tick)
  end
end
assertEquals(fleeEntries, 10,
  "mixed simulation should accept each scheduled FLEE interruption")
assertEquals(fleeExits, 10,
  "mixed simulation should recover from each scheduled FLEE episode")
assertEquals(mixed.runtimeState.state, "SETTLED",
  "mixed simulation must end under ordinary behavior ownership")
assertEquals(mixed.runtimeState.targetEntityId, nil,
  "mixed simulation must not end with stale threat identity")
assertEquals(mixed.runtimeState.fleeExecution, nil,
  "mixed simulation must not end with stale FLEE planner state")

return true