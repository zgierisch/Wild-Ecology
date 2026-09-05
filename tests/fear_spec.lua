local Fear = require("src.behavior.fear")
local Controller = require("src.behavior.controller")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertNear(actual, expected, tolerance, message)
  if math.abs(actual - expected) > (tolerance or 0.000001) then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function socialEntity(id, independence)
  return {
    id = id,
    species = "PIDGEY",
    ecology = { archetype = "flocking_bird", family = "A" },
    temperament = { sociability = 0.8, boldness = 0.2 },
    rawStats = { independence = independence or 0.2 },
    relationships = {},
    runtimeState = {}
  }
end

local observer = socialEntity("observer", 0.2)
local relationshipsBefore = observer.relationships
local nearSocial, nearDetails = Fear.socialInput(observer, {
  { id = "source", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = 1, dy = 0 } }
}, 5)
local farSocial = Fear.socialInput(observer, {
  { id = "source", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 5, conspecific = true, escapeBias = { dx = 1, dy = 0 } }
}, 5)
assertTrue(nearSocial > farSocial, "social fear should attenuate with distance")
assertEquals(Fear.socialInput(observer, {
  { id = "source", alarmOutput = 1, alarmGroundedness = 1, state = "FLEE", distance = 6, conspecific = true }
}, 5), 0, "social fear should remain local")
assertEquals(nearDetails.escapeBias.dx > 0, true, "social alarm should preserve only the visible escape direction")

local combined = Fear.socialInput(observer, {
  { id = "a", alarmOutput = 0.8, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true },
  { id = "b", alarmOutput = 0.8, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true }
}, 5)
assertTrue(combined > nearSocial and combined <= nearSocial * 1.35, "corroboration should be useful but bounded by the strongest source")

local independent = socialEntity("independent", 0.95)
local independentFear = Fear.socialInput(independent, {
  { id = "source", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true }
}, 5)
assertTrue(independentFear < nearSocial, "independence should reduce social fear susceptibility")

local current = Fear.update(observer, {
  socialSources = {
    { id = "source", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = 1, dy = 0 } }
  },
  perceptionRadius = 5
}, 10)
local decayed = Fear.update(observer, { socialSources = {}, perceptionRadius = 5 }, 25)
assertTrue(current > decayed and decayed >= 0, "fear should decay by elapsed simulation ticks")
assertEquals(observer.relationships, relationshipsBefore, "social fear must not replace the persistent relationship table")
assertEquals(observer.relationships.source, nil, "social fear must not create threat memory for an unseen threat")
assertEquals(observer.runtimeState.directThreatId, nil, "social alarm must not copy the source's threat identity")

local triggerLow, safetyLow = Fear.escapeDistances(4, 0)
local triggerHigh, safetyHigh = Fear.escapeDistances(4, 1)
assertEquals(triggerLow, 4, "zero fear should preserve the base trigger radius")
assertTrue(triggerHigh > triggerLow, "fear should expand trigger distance")
assertTrue(safetyHigh > triggerHigh and safetyHigh <= 12, "desired safety should be separate and bounded")

local alarmed = socialEntity("alarmed", 0.2)
alarmed.runtimeState.fearCurrent = 0.8
alarmed.runtimeState.fearSocial = 0.8
alarmed.runtimeState.socialEscapeBiasConfidence = 0.8
local state = Controller.tick(alarmed, {}, nil, {
  hasTarget = false,
  purposefulTarget = false,
  allowTargeting = false,
  currentFear = 0.8,
  position = { cellX = 5, cellY = 5 },
  targetPositions = {},
  socialAlarmTargetPosition = { cellX = 2, cellY = 5 },
  fleeSafetyDistance = 7
}, 30)
assertEquals(state, "FLEE", "strong targetless social alarm should enter the ordinary FLEE state")
assertEquals(alarmed.runtimeState.targetEntityId, nil, "social FLEE should not invent a threat target id")
assertEquals(alarmed.runtimeState.movementRequest.direction, "RIGHT", "social FLEE should follow the observed escape direction")

local function decideSocialOnlyFear(id, socialFear)
  local entity = socialEntity(id, 0.2)
  entity.runtimeState.fearCurrent = socialFear
  entity.runtimeState.fearSocial = socialFear
  entity.runtimeState.socialEscapeBiasConfidence = 0.8
  local selected = Controller.tick(entity, {}, nil, {
    hasTarget = false,
    purposefulTarget = false,
    allowTargeting = false,
    currentFear = socialFear,
    position = { cellX = 5, cellY = 5 },
    targetPositions = {},
    socialAlarmTargetPosition = { cellX = 2, cellY = 5 }
  }, 30)
  return entity, selected
end

local liveSocial, liveSocialState = decideSocialOnlyFear("live-social", 0.16)
assertEquals(liveSocialState, "SETTLED",
  "live-equivalent social fear should lose to passive equilibrium")
assertEquals(liveSocial.runtimeState.socialFleeEligible, true,
  "social FLEE utility should remain eligible below the .22 cue threshold")
assertEquals(liveSocial.runtimeState.socialFleeCueEligible, false,
  ".22 should gate strong coherent social-cue bookkeeping")
assertEquals(liveSocial.runtimeState.socialFleeDecisionReason, "FLEE_SCORE_NOT_WINNER",
  "social decision diagnostics should identify utility rather than misreporting ineligibility")
assertEquals(liveSocial.runtimeState.behaviorScores.FLEE, 9.6,
  "live-equivalent social fear should retain its unmodified utility contribution")

local gatedSocial, gatedSocialState = decideSocialOnlyFear("gated-social", 0.22)
assertEquals(gatedSocial.runtimeState.socialFleeCueEligible, true,
  "the documented fear and confidence thresholds should make the directional cue eligible")
assertEquals(gatedSocialState, "SETTLED",
  "cue eligibility alone should not bypass the ordinary utility winner")
assertEquals(gatedSocial.runtimeState.socialFleeDecisionReason, "FLEE_SCORE_NOT_WINNER",
  "diagnostics should distinguish a passed cue gate from a losing FLEE utility score")
assertEquals(gatedSocial.runtimeState.behaviorScores.FLEE, 13.2,
  "the threshold fixture should retain the current social FLEE coefficient")
assertEquals(gatedSocial.runtimeState.behaviorScores.SETTLED, 20,
  "the fixture should expose the competing passive-equilibrium score")

local belowCueWinner = socialEntity("below-cue-winner", 0.2)
belowCueWinner.temperament.sociability = 0
belowCueWinner.runtimeState.fearCurrent = 0.21
belowCueWinner.runtimeState.fearSocial = 0.21
belowCueWinner.runtimeState.socialEscapeBiasConfidence = 0.8
local belowCueState = Controller.tick(belowCueWinner, {}, nil, {
  hasTarget = false,
  purposefulTarget = false,
  allowTargeting = false,
  currentFear = 0.21,
  position = { cellX = 5, cellY = 5 },
  targetPositions = {},
  socialAlarmTargetPosition = { cellX = 2, cellY = 5 }
}, 30)
assertEquals(belowCueWinner.runtimeState.socialFleeCueEligible, false,
  "fear below .22 should not establish the strong social cue category")
assertEquals(belowCueState, "SETTLED",
  "weak targetless social fear should not disturb passive equilibrium")

local tiedSocial, tiedSocialState = decideSocialOnlyFear("tied-social", 1 / 3)
assertNear(tiedSocial.runtimeState.behaviorScores.FLEE, 20, 0.000001,
  "representative Pidgey FLEE should tie SETTLED at social fear one-third")
assertEquals(tiedSocialState, "SETTLED", "SETTLED should win the exact utility tie")
local winningSocial, winningSocialState = decideSocialOnlyFear("winning-social", 0.334)
assertEquals(winningSocialState, "FLEE",
  "representative uncommitted Pidgey should select FLEE above passive utility")

local function socialAgainstCommittedSeek(id, socialFear)
  local entity = socialEntity(id, 0.2)
  entity.runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 0 }
  local context = {
    hasTarget = false,
    purposefulTarget = false,
    allowTargeting = false,
    currentFear = 0,
    position = { cellX = 5, cellY = 5 },
    targetPositions = {},
    socialAlarmTargetPosition = { cellX = 2, cellY = 5 },
    flockSearch = {
      utility = 14.4,
      nearbySameSpecies = 0,
      cueSource = "social_signal",
      cueDirection = "EAST",
      targetEntityId = "hidden-family"
    }
  }
  Controller.tick(entity, {}, nil, context, 1)
  entity.runtimeState.fearCurrent = socialFear
  entity.runtimeState.fearSocial = socialFear
  entity.runtimeState.socialEscapeBiasConfidence = 0.8
  context.currentFear = socialFear
  return entity, Controller.tick(entity, {}, nil, context, 30)
end

local heldSeek, heldSeekState = socialAgainstCommittedSeek("held-seek", 0.651)
assertEquals(heldSeekState, "SEEK_FLOCK",
  "social FLEE below the current score plus episode commitment margin should not interrupt")
assertEquals(heldSeek.runtimeState.switchReason, "ACTIVE_PURPOSE_COMMITMENT",
  "the active purposeful episode should own the interruption threshold")
local interruptedSeek, interruptedSeekState = socialAgainstCommittedSeek("interrupted-seek", 0.653)
assertEquals(interruptedSeekState, "FLEE",
  "social FLEE above the representative commitment threshold should interrupt SEEK_FLOCK")

local smoothing = socialEntity("smoothing", 0.2)
local function observeDirection(dx, tick)
  Fear.update(smoothing, {
    socialSources = {
      { id = "neighbor", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = dx, dy = 0 } }
    },
    perceptionRadius = 5
  }, tick)
end
observeDirection(-1, 1)
observeDirection(-1, 2)
observeDirection(-1, 3)
observeDirection(1, 4)
assertTrue(smoothing.runtimeState.socialEscapeBias.dx < 0, "one contradictory observation must not reverse a stable social cue")
observeDirection(1, 5)
observeDirection(1, 6)
observeDirection(1, 7)
observeDirection(1, 8)
assertTrue(smoothing.runtimeState.socialEscapeBias.dx > 0, "sustained coherent evidence should eventually reverse social direction")
assertTrue(smoothing.runtimeState.socialEscapeBiasConfidence > 0, "coherent motion should expose directional confidence")
assertEquals(smoothing.runtimeState.directThreatId, nil, "smoothed social direction must not transfer threat identity")

local incoherent = socialEntity("incoherent", 0.2)
Fear.update(incoherent, {
  socialSources = {
    { id = "left", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = -1, dy = 0 } },
    { id = "right", alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = 1, dy = 0 } }
  },
  perceptionRadius = 5
}, 1)
assertTrue(incoherent.runtimeState.fearSocial > 0.4, "incoherent frightened neighbors should still propagate alarm")
assertTrue(incoherent.runtimeState.socialEscapeBiasConfidence < 0.2, "conflicting movement should provide little directional confidence")

local hysteresis = socialEntity("flee-hysteresis", 0.2)
hysteresis.runtimeState.state = "FLEE"
hysteresis.runtimeState.stateEnteredTick = 1
hysteresis.runtimeState.fearCurrent = 0.13
local heldFlee = Controller.tick(hysteresis, {}, 5, {
  hasTarget = true,
  purposefulTarget = true,
  targetEntityId = "player",
  currentFear = 0.13,
  position = { cellX = 5, cellY = 5 },
  targetPositions = { player = { cellX = 0, cellY = 5 } },
  allowTargeting = false
}, 40)
assertEquals(heldFlee, "FLEE", "FLEE should continue between its entry and safe-exit thresholds")
hysteresis.runtimeState.fearCurrent = 0.05
local exitedFlee
for tick = 41, 70 do
  exitedFlee = Controller.tick(hysteresis, {}, 6, {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = "player",
    currentFear = 0.05,
    position = { cellX = 6, cellY = 5 },
    targetPositions = { player = { cellX = 0, cellY = 5 } },
    allowTargeting = false
  }, tick)
  if tick == 41 then
    assertEquals(hysteresis.runtimeState.fleeExitBlockedReason, "RECOVERY_HOLD",
      "the first safe tick should begin sustained-safe recovery rather than exit immediately")
  end
end
assertTrue(exitedFlee ~= "FLEE", "FLEE should exit after sustained safe distance and low fear")

local feedbackA = socialEntity("feedback-a", 0.2)
local feedbackB = socialEntity("feedback-b", 0.2)
for tick = 1, 8 do
  local directionA = tick <= 4 and -1 or 1
  local directionB = tick <= 5 and -1 or 1
  Fear.update(feedbackA, {
    socialSources = {
      { id = feedbackB.id, alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = directionB, dy = 0 } }
    }, perceptionRadius = 5
  }, tick)
  Fear.update(feedbackB, {
    socialSources = {
      { id = feedbackA.id, alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1, conspecific = true, escapeBias = { dx = directionA, dy = 0 } }
    }, perceptionRadius = 5
  }, tick)
  if tick == 5 then
    assertTrue(feedbackA.runtimeState.socialEscapeBias.dx < 0 and feedbackB.runtimeState.socialEscapeBias.dx < 0,
      "one actor's reversal must not immediately turn mutual social feedback into a direction flip")
  end
end
assertTrue(feedbackA.runtimeState.socialEscapeBias.dx > 0 and feedbackB.runtimeState.socialEscapeBias.dx > 0,
  "mutual social cues should transition only after sustained coherent reversal evidence")

local function sourceSnapshot(source, observerId, distance, escapeBias)
  local runtime = source.runtimeState
  return {
    id = source.id,
    species = source.species,
    ecology = source.ecology,
    alarmOutput = runtime.alarmOutput or 0,
    alarmDirectComponent = runtime.alarmDirectComponent or 0,
    alarmRelayedComponent = runtime.alarmRelayedComponent or 0,
    alarmGroundedness = runtime.alarmGroundedness or 0,
    echoContribution = runtime.socialContributionBySource
      and runtime.socialContributionBySource[observerId] or 0,
    socialInputRaw = runtime.socialInputRaw or 0,
    state = runtime.state or "FLEE",
    distance = distance or 1,
    relationship = {},
    escapeBias = escapeBias
  }
end

local function cadence(entities, neighbors, tick, directById)
  local snapshots = {}
  for _, entity in ipairs(entities) do
    snapshots[entity.id] = sourceSnapshot(entity, nil, 1)
  end
  for _, entity in ipairs(entities) do
    local sources = {}
    for _, neighbor in ipairs(neighbors[entity.id] or {}) do
      local snapshot = snapshots[neighbor.entity.id]
      snapshot.echoContribution = neighbor.entity.runtimeState.socialContributionBySource
        and neighbor.entity.runtimeState.socialContributionBySource[entity.id] or 0
      snapshot.distance = neighbor.distance or 1
      snapshot.escapeBias = neighbor.escapeBias
      sources[#sources + 1] = snapshot
    end
    local direct = directById and directById[entity.id] or nil
    Fear.update(entity, {
      relationship = direct and { hostility = direct.hostility or 100 } or {},
      threatDistance = direct and (direct.distance or 1) or nil,
      perceivedFear = direct and (direct.perceivedFear or 0) or 0,
      socialSources = sources,
      perceptionRadius = direct and direct.radius or 1
    }, tick)
  end
end

local chain = {}
local chainNeighbors = {}
for index = 1, 5 do
  chain[index] = socialEntity("chain-" .. index, 0.2)
  chain[index].runtimeState.state = "FLEE"
end
for index = 1, 5 do
  chainNeighbors[chain[index].id] = {}
  if index > 1 then chainNeighbors[chain[index].id][#chainNeighbors[chain[index].id] + 1] = { entity = chain[index - 1] } end
  if index < 5 then chainNeighbors[chain[index].id][#chainNeighbors[chain[index].id] + 1] = { entity = chain[index + 1] } end
end
for tick = 1, 8 do
  cadence(chain, chainNeighbors, 100 + tick, { [chain[1].id] = { hostility = 100, distance = 1, radius = 1 } })
end
assertTrue(chain[1].runtimeState.alarmOutput > chain[2].runtimeState.alarmOutput
  and chain[2].runtimeState.alarmOutput > chain[3].runtimeState.alarmOutput
  and chain[3].runtimeState.alarmOutput > chain[4].runtimeState.alarmOutput
  and chain[4].runtimeState.alarmOutput >= chain[5].runtimeState.alarmOutput,
  "a linear social relay should lose transmissible alarm at every hop")
assertTrue(chain[2].runtimeState.fearSocial > 0.15, "the first social receiver should still become meaningfully frightened")
assertTrue(chain[5].runtimeState.fearSocial < 0.12, "a sparse distal receiver should receive little alarm")

local echoA = socialEntity("echo-a", 0.2)
local echoB = socialEntity("echo-b", 0.2)
for _, entity in ipairs({ echoA, echoB }) do
  entity.runtimeState.state = "FLEE"
  entity.runtimeState.fearCurrent = 0.55
  entity.runtimeState.fearSocial = 0.55
  entity.runtimeState.alarmOutput = 0.25
  entity.runtimeState.alarmRelayedComponent = 0.25
  entity.runtimeState.alarmGroundedness = 0.1
end
local echoNeighbors = {
  [echoA.id] = { { entity = echoB } },
  [echoB.id] = { { entity = echoA } }
}
for tick = 1, 55 do cadence({ echoA, echoB }, echoNeighbors, 200 + tick) end
assertTrue(echoA.runtimeState.fearCurrent < 0.15 and echoB.runtimeState.fearCurrent < 0.15,
  string.format("mutual residual social fear should decay instead of sustaining itself (A=%.3f B=%.3f)",
    echoA.runtimeState.fearCurrent, echoB.runtimeState.fearCurrent))
assertTrue((echoA.runtimeState.echoSuppressedAmount or 0) >= 0 and (echoB.runtimeState.echoSuppressedAmount or 0) >= 0,
  "mutual social updates should expose echo suppression diagnostics")

local supportedA = socialEntity("supported-a", 0.2)
local supportedB = socialEntity("supported-b", 0.2)
supportedA.runtimeState.state = "FLEE"
supportedB.runtimeState.state = "FLEE"
local supportedNeighbors = {
  [supportedA.id] = { { entity = supportedB } },
  [supportedB.id] = { { entity = supportedA } }
}
for tick = 1, 12 do
  cadence({ supportedA, supportedB }, supportedNeighbors, 260 + tick, {
    [supportedA.id] = { hostility = 100, distance = 1, radius = 1 }
  })
end
assertTrue(supportedB.runtimeState.fearSocial > 0.15,
  "one external direct source should meaningfully frighten its social neighbor")
assertTrue(supportedA.runtimeState.fearCurrent <= 1 and supportedB.runtimeState.fearCurrent <= 1,
  "mutual feedback must not amplify beyond the bounded grounded input")
for tick = 1, 90 do cadence({ supportedA, supportedB }, supportedNeighbors, 280 + tick) end
assertTrue(supportedA.runtimeState.fearCurrent < 0.15 and supportedB.runtimeState.fearCurrent < 0.15,
  string.format("removing the external source should let the supported social loop decay (A=%.3f B=%.3f directA=%.3f)",
    supportedA.runtimeState.fearCurrent, supportedB.runtimeState.fearCurrent,
    supportedA.runtimeState.fearDirect or 0))

local function denseCrowd(withDirectSource)
  local crowd, neighbors = {}, {}
  for index = 1, 8 do
    local entity = socialEntity("crowd-" .. tostring(withDirectSource) .. "-" .. index, 0.2)
    entity.runtimeState.state = "FLEE"
    entity.runtimeState.fearCurrent = 0.6
    entity.runtimeState.fearSocial = 0.6
    entity.runtimeState.alarmOutput = 0.25
    entity.runtimeState.alarmRelayedComponent = 0.25
    entity.runtimeState.alarmGroundedness = 0.1
    crowd[index] = entity
  end
  for _, entity in ipairs(crowd) do
    neighbors[entity.id] = {}
    for _, other in ipairs(crowd) do
      if other ~= entity then neighbors[entity.id][#neighbors[entity.id] + 1] = { entity = other } end
    end
  end
  for tick = 1, 55 do
    local direct = withDirectSource and { [crowd[1].id] = { hostility = 100, distance = 1, radius = 1 } } or nil
    cadence(crowd, neighbors, 300 + tick, direct)
  end
  local total = 0
  for _, entity in ipairs(crowd) do total = total + entity.runtimeState.fearCurrent end
  return crowd, total / #crowd
end

local residualCrowd, residualAverage = denseCrowd(false)
local groundedCrowd, groundedAverage = denseCrowd(true)
assertTrue(residualAverage < 0.25, "a dense social-only crowd should not maintain near-maximal fear")
assertTrue(groundedAverage > residualAverage + 0.1, "a live direct source should sustain stronger crowd panic")
assertTrue(groundedCrowd[2].runtimeState.fearSocial > 0.15, "grounded panic should still recruit nearby social animals")

local stampede = {}
local stampedeNeighbors = {}
for index = 1, 6 do
  stampede[index] = socialEntity("stampede-" .. index, 0.2)
  stampede[index].runtimeState.state = "FLEE"
  stampedeNeighbors[stampede[index].id] = {}
end
for index = 1, 6 do
  if index > 1 then stampedeNeighbors[stampede[index].id][#stampedeNeighbors[stampede[index].id] + 1] = { entity = stampede[index - 1], escapeBias = { dx = 1, dy = 0 } } end
  if index < 6 then stampedeNeighbors[stampede[index].id][#stampedeNeighbors[stampede[index].id] + 1] = { entity = stampede[index + 1], escapeBias = { dx = 1, dy = 0 } } end
end
for tick = 1, 10 do
  cadence(stampede, stampedeNeighbors, 400 + tick, { [stampede[1].id] = { hostility = 100, distance = 1, radius = 1 } })
end
assertTrue(stampede[2].runtimeState.fearSocial > 0.15 and stampede[3].runtimeState.fearSocial > 0.05,
  "a grounded alarm should propagate meaningful panic through part of a group")
assertTrue(stampede[2].runtimeState.socialEscapeBiasConfidence > 0.2,
  "coherent visible escape directions should survive relay attenuation")
assertEquals(stampede[3].runtimeState.directThreatId, nil, "emergent panic must not carry hidden threat identity")

local calmDiagnostics = {}
for _ = 1, 100 do
  assertEquals(Fear.diagnosticEvent(calmDiagnostics, false), nil,
    "stable calm fear must not emit NORMAL diagnostics")
end

local decayingDiagnostics = {
  fearCurrent = 0.32,
  fearDirect = 0.32,
  directThreatId = "player",
  threatAssessment = { primaryThreatReason = "HOSTILITY" },
  state = "FLEE"
}
assertEquals(Fear.diagnosticEvent(decayingDiagnostics, false), "INITIAL_ACTIVE",
  "initial active fear should emit one diagnostic")
local decayEvents = 0
for step = 1, 32 do
  decayingDiagnostics.fearCurrent = math.max(0, 0.32 - step * 0.01)
  decayingDiagnostics.fearDirect = decayingDiagnostics.fearCurrent
  if step == 1 then
    decayingDiagnostics.directThreatId = nil
    decayingDiagnostics.threatAssessment.primaryThreatReason = nil
  end
  if decayingDiagnostics.fearCurrent < 0.12 then decayingDiagnostics.state = "IDLE" end
  if Fear.diagnosticEvent(decayingDiagnostics, false) then decayEvents = decayEvents + 1 end
end
assertTrue(decayEvents >= 4 and decayEvents <= 12,
  "gradual decay should emit sparse accumulated deltas, band edges, and final calm")

local socialDiagnostics = {}
Fear.diagnosticEvent(socialDiagnostics, false)
socialDiagnostics.fearCurrent = 0.3
socialDiagnostics.fearSocial = 0.3
socialDiagnostics.nearbyFearSources = 1
socialDiagnostics.strongestFearSource = "neighbor"
assertTrue(Fear.diagnosticEvent(socialDiagnostics, false) ~= nil,
  "a social fear spike should emit a NORMAL diagnostic")
assertEquals(Fear.diagnosticEvent(socialDiagnostics, true), "TRACE",
  "focused TRACE should emit every emotional integration")
assertEquals(Fear.diagnosticEvent(socialDiagnostics, false), nil,
  "non-focused stable fear should remain suppressed")

return true