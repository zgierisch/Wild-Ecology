local Controller = require("src.behavior.controller")
local AgentAudit = require("src.debug.agent_audit")
local Entity = require("src.entities.entity")
local RelationshipAudit = require("src.debug.relationship_audit")
local Relationships = require("src.entities.relationships")
local Social = require("src.behavior.social")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local observer = Entity.newWildPokemon({
  id = "wild:investigation:observer",
  species = "PIDGEY",
  level = 5,
  personalitySeed = 1,
  home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = 1, spawnY = 1 }
})
local completedSubjectId = "wild:investigation:subject-b"
local nextThreatId = "wild:investigation:subject-c"
local completedRelationship = Relationships.getOrCreate(observer,
  completedSubjectId)
completedRelationship.familiarity = 1
completedRelationship.affinity = 2
local nextRelationship = Relationships.getOrCreate(observer, nextThreatId)
nextRelationship.familiarity = 11
nextRelationship.affinity = 12
nextRelationship.threatMemory = 80
nextRelationship.directThreatMemory = 80

observer.runtimeState = {
  state = "INVESTIGATE",
  stateEnteredTick = 0,
  targetEntityId = completedSubjectId,
  fearCurrent = 1,
  intentEpisode = {
    intent = "INVESTIGATE",
    targetId = completedSubjectId,
    startedTick = 0,
    status = "ACTIVE",
    lastProgressTick = 0,
    progress = 0,
    commitment = 6,
    failedAttempts = 0
  }
}

local mutations = {}
Relationships.setMutationSink(function(mutation)
  if mutation.event == "INVESTIGATION_COMPLETED" then
    mutations[#mutations + 1] = mutation
  end
end)

local state = Controller.tick(observer, nextRelationship, 1, {
  hasTarget = true,
  purposefulTarget = true,
  targetEntityId = nextThreatId,
  candidates = {
    { id = nextThreatId, distance = 1, novelty = 0 }
  },
  position = { cellX = 1, cellY = 1 },
  targetPositions = {
    [completedSubjectId] = { cellX = 2, cellY = 1 },
    [nextThreatId] = { cellX = 1, cellY = 2 }
  },
  threatAssessment = {
    primaryThreatId = nextThreatId,
    primaryThreatDistance = 1,
    primaryThreatReason = "DIRECT_THREAT_MEMORY",
    primaryThreatSevere = true
  },
  currentFear = 1,
  goalRadius = 1,
  investigateRadius = 3
}, 10)

assertEquals(state, "FLEE", "the next behavior should legitimately retarget to C")
assertEquals(#mutations, 1,
  "leaving INVESTIGATE should emit exactly one completion mutation")
assertEquals(mutations[1].subjectId, completedSubjectId,
  "completion mutation must carry the completed episode target")
assertEquals(mutations[1].relationshipRef, completedRelationship,
  "completion must mutate the canonical A-to-B relationship object")
assertEquals(observer.relationships[completedSubjectId], completedRelationship,
  "canonical A-to-B identity must remain stable")
assertEquals(completedRelationship.familiarity, 31,
  "ten investigation ticks should add the unchanged +30 familiarity to B")
assertEquals(nextRelationship.familiarity, 11,
  "retargeting to C must not apply B's completion reward to C")

Relationships.setMutationSink(nil)

local function newObserver(id, seed)
  return Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 5,
    personalitySeed = seed,
    home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = seed, spawnY = 1 }
  })
end

local function beginInvestigation(entity, targetId, enteredTick)
  entity.runtimeState = {
    state = "INVESTIGATE",
    stateEnteredTick = enteredTick,
    targetEntityId = targetId,
    intentEpisode = {
      intent = "INVESTIGATE",
      targetId = targetId,
      startedTick = enteredTick,
      status = "ACTIVE",
      lastProgressTick = enteredTick,
      progress = 0,
      commitment = 6,
      failedAttempts = 0
    }
  }
end

local function completeToward(entity, relationship, completedTargetId,
  selectedTargetId, tick, mode)
  local selectedDistance = mode == "APPROACH" and 4 or 1
  local context = {
    hasTarget = true,
    purposefulTarget = true,
    targetEntityId = selectedTargetId,
    candidates = {
      { id = selectedTargetId, distance = selectedDistance, novelty = 0 }
    },
    position = { cellX = 1, cellY = 1 },
    targetPositions = {
      [completedTargetId] = { cellX = 2, cellY = 1 },
      [selectedTargetId] = { cellX = 1 + selectedDistance, cellY = 1 }
    },
    currentFear = 0,
    goalRadius = 1,
    investigateRadius = 3
  }
  if mode == "FLEE" then
    context.currentFear = 1
    context.threatAssessment = {
      primaryThreatId = selectedTargetId,
      primaryThreatDistance = 1,
      primaryThreatReason = "DIRECT_THREAT_MEMORY",
      primaryThreatSevere = true
    }
  elseif mode == "SEEK_FLOCK" then
    context.flockSearch = {
      utility = 100,
      targetEntityId = selectedTargetId,
      cuePosition = { cellX = 1, cellY = 2 },
      nearbySameSpecies = 0
    }
  end
  return Controller.tick(entity, relationship, 1, context, tick)
end

local function seededRelationship(entity, targetId, familiarity, affinity,
  trust)
  local relationship = Relationships.getOrCreate(entity, targetId)
  relationship.familiarity = familiarity
  relationship.affinity = affinity
  relationship.trust = trust or 0
  return relationship
end

-- A completed target remains authoritative when the next purposeful target
-- changes without an emergency.
local approachObserver = newObserver("wild:investigation:approach", 2)
local approachB = seededRelationship(approachObserver, "approach-b", 1, 2)
local approachC = seededRelationship(approachObserver, "approach-c", 100, 100,
  100)
beginInvestigation(approachObserver, "approach-b", 0)
local approachState = completeToward(approachObserver, approachC, "approach-b",
  "approach-c", 40, "APPROACH")
assertEquals(approachState, "APPROACH",
  "normal purposeful reselection should target C")
assertEquals(approachB.familiarity, 31,
  "normal retargeting must reward completed B")
assertEquals(approachC.familiarity, 100,
  "normal retargeting must not reward selected C")

-- SEEK_FLOCK owns its new target independently of completed investigation.
local flockObserver = newObserver("wild:investigation:flock", 3)
local flockB = seededRelationship(flockObserver, "flock-b", 1, 2)
local flockC = seededRelationship(flockObserver, "flock-c", 11, 12)
beginInvestigation(flockObserver, "flock-b", 0)
local flockState = completeToward(flockObserver, flockC, "flock-b", "flock-c",
  40, "SEEK_FLOCK")
assertEquals(flockState, "SEEK_FLOCK",
  "social navigation should become the next behavior")
assertEquals(flockB.familiarity, 31,
  "SEEK_FLOCK handoff must reward completed B")
assertEquals(flockC.familiarity, 11,
  "SEEK_FLOCK target C must not receive B's completion reward")

-- One observer can investigate B/C/D without an observer-owned accumulator.
local multiObserver = newObserver("wild:investigation:multi", 4)
local playerRelationship = seededRelationship(multiObserver, "player", 0, 0)
playerRelationship.threatMemory = 80
playerRelationship.directThreatMemory = 80
local subjectIds = { "multi-b", "multi-c", "multi-d" }
local expectedFamiliarity = { 1, 11, 21 }
local expectedAffinity = { 2, 12, 22 }
local subjectRelationships = {}
for index, subjectId in ipairs(subjectIds) do
  subjectRelationships[index] = seededRelationship(multiObserver, subjectId,
    expectedFamiliarity[index], expectedAffinity[index])
end
for index, subjectId in ipairs(subjectIds) do
  beginInvestigation(multiObserver, subjectId, index * 20)
  local completionTick = index * 20 + 10
  assertEquals(completeToward(multiObserver, playerRelationship, subjectId,
    "player", completionTick, "FLEE"), "FLEE",
    "each completion may legitimately hand off to FLEE")
  for checkIndex, relationship in ipairs(subjectRelationships) do
    local expected = expectedFamiliarity[checkIndex]
      + (checkIndex <= index and 30 or 0)
    assertEquals(relationship.familiarity, expected,
      "only the completed B/C/D relationship should change")
    assertEquals(relationship.affinity, expectedAffinity[checkIndex],
      "investigation completion must not change affinity")
  end
end
assertEquals(playerRelationship.familiarity, 0,
  "the observer's recurring player relationship must not accumulate rewards")

-- High values evolve continuously and later directed events retain identity.
local continuityObserver = newObserver("wild:investigation:continuity", 5)
local continuityB = seededRelationship(continuityObserver, "continuity-b", 90,
  95, 7)
local continuityBObject = continuityB
beginInvestigation(continuityObserver, "continuity-b", 0)
completeToward(continuityObserver, continuityB, "continuity-b",
  "continuity-b", 40, "APPROACH")
assertEquals(continuityB.familiarity, 100,
  "high familiarity should clamp continuously rather than reset")
assertEquals(continuityB.trust, 7,
  "investigation completion must not change trust")
assertEquals(continuityB.affinity, 95,
  "investigation completion must not change affinity")
Social.observeNearby(continuityObserver, "continuity-b", 1, 41, {
  id = "continuity-b", species = "PIDGEY", ecology = { family = "BIRD" }
})
Relationships.applyPerceptionEvent(continuityObserver, "continuity-b",
  "ENTITY_RETREATING", { fearRelief = 1 }, 42)
assertEquals(continuityObserver.relationships["continuity-b"],
  continuityBObject,
  "SOCIAL_NEARBY and ENTITY_RETREATING must retain canonical identity")
assertEquals(continuityObserver.relationships[continuityObserver.id], nil,
  "directed completion must not create a reverse relationship")

local directedObserver = newObserver("wild:investigation:directed-a", 31)
local directedSubject = newObserver("wild:investigation:directed-b", 32)
local directedRelationship = seededRelationship(directedObserver,
  directedSubject.id, 1, 100, 100)
beginInvestigation(directedObserver, directedSubject.id, 0)
completeToward(directedObserver, directedRelationship, directedSubject.id,
  directedSubject.id, 40, "APPROACH")
assertEquals(directedSubject.relationships[directedObserver.id], nil,
  "A investigating B must not create or mutate B-to-A")

-- Relationship and agent audits must see the same canonical A-to-B table.
local auditObserver = newObserver("wild:investigation:audit", 6)
local auditB = seededRelationship(auditObserver, "audit-b", 1, 2)
local auditC = seededRelationship(auditObserver, "audit-c", 100, 100, 100)
local relationshipAudit = RelationshipAudit.new({ writer = function() end })
local agentAudit = AgentAudit.new({
  writer = function() end,
  forensicEnabled = false
})
local auditCompletion = nil
Relationships.setMutationSink(function(mutation)
  local _, emission = relationshipAudit:observe(mutation)
  agentAudit:observeMutation(mutation, emission)
  if mutation.event == "INVESTIGATION_COMPLETED" then
    auditCompletion = mutation
  end
end)
Relationships.applyPerceptionEvent(auditObserver, "audit-b",
  "ENTITY_RETREATING", { fearRelief = 1 }, 1)
beginInvestigation(auditObserver, "audit-b", 1)
completeToward(auditObserver, auditC, "audit-b", "audit-c", 41, "APPROACH")
Social.observeNearby(auditObserver, "audit-b", 1, 42, {
  id = "audit-b", species = "PIDGEY", ecology = { family = "BIRD" }
})
if not auditCompletion then
  error("canonical investigation completion mutation was not observed")
end
assertEquals(auditCompletion.subjectId, "audit-b",
  "relationship audit mutation must identify completed B")
assertEquals(auditCompletion.relationshipRef, auditB,
  "both audits must receive canonical A-to-B identity")
assertEquals(agentAudit:snapshot().objectReplacements, 0,
  "legitimate completion and follow-up must produce no replacement anomaly")
assertEquals(relationshipAudit:snapshot().relationshipAuditRecordsWritten > 0,
  true,
  "canonical completion should remain visible in relationship journal")

-- Runtime reconstruction is a hard boundary, but a new episode still owns
-- and mutates the same durable relationship.
auditObserver.runtimeState = nil
beginInvestigation(auditObserver, "audit-b", 50)
completeToward(auditObserver, auditC, "audit-b", "audit-c", 90, "APPROACH")
assertEquals(auditObserver.relationships["audit-b"], auditB,
  "new runtime investigation must reuse durable canonical A-to-B")
assertEquals(agentAudit:snapshot().objectReplacements, 0,
  "runtime reconstruction must not imply relationship replacement")

-- Live-like repetition: ten observers, three subjects, and a player handoff.
local completionCount = 0
local wrongSubjectMutations = 0
local stressAgentAudit = AgentAudit.new({
  writer = function() end,
  forensicEnabled = false
})
for observerIndex = 1, 10 do
  local stressObserver = newObserver(
    "wild:investigation:stress:" .. observerIndex, 10 + observerIndex)
  local stressPlayer = seededRelationship(stressObserver, "player", 0, 0)
  stressPlayer.threatMemory = 80
  stressPlayer.directThreatMemory = 80
  for subjectIndex = 1, 3 do
    local subjectId = "stress-subject:" .. subjectIndex
    local canonical = seededRelationship(stressObserver, subjectId,
      subjectIndex, subjectIndex + 1)
    beginInvestigation(stressObserver, subjectId, subjectIndex * 20)
    local observedMutation = nil
    Relationships.setMutationSink(function(mutation)
      stressAgentAudit:observeMutation(mutation)
      if mutation.event == "INVESTIGATION_COMPLETED" then
        completionCount = completionCount + 1
        observedMutation = mutation
      end
    end)
    completeToward(stressObserver, stressPlayer, subjectId, "player",
      subjectIndex * 20 + 10, "FLEE")
    if not observedMutation or observedMutation.subjectId ~= subjectId
      or observedMutation.relationshipRef ~= canonical then
      wrongSubjectMutations = wrongSubjectMutations + 1
    end
  end
end
assertEquals(completionCount, 30,
  "every live-like completed interaction should emit once")
assertEquals(wrongSubjectMutations, 0,
  "live-like repetition must produce no wrong-subject mutation")
assertEquals(stressAgentAudit:snapshot().objectReplacements, 0,
  "live-like canonical completion must produce no replacement anomaly")

-- Direct threat remains immediate, directed, and independent.
local threatObserver = newObserver("wild:investigation:threat", 30)
local threatSubjectId = "threat-subject"
local threatRelationship = Relationships.applyPerceptionEvent(threatObserver,
  threatSubjectId, "ENTITY_ATTACKED", { threatDelta = 4 }, 1)
if not threatRelationship then
  error("direct threat relationship was not created")
end
assertEquals(threatRelationship.directThreatMemory, 4,
  "direct threat learning must remain immediate")
assertEquals(threatObserver.relationships[threatSubjectId], threatRelationship,
  "direct threat must use canonical directed relationship")

Relationships.setMutationSink(nil)

return true