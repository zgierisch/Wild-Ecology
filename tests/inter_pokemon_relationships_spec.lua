local Entity = require("src.entities.entity")
local Fear = require("src.behavior.fear")
local Perception = require("src.world.perception")
local Relationships = require("src.entities.relationships")
local RuntimeState = require("src.core.runtime_state")
local Social = require("src.behavior.social")
local TargetSelector = require("src.behavior.target_selector")
local Utility = require("src.behavior.utility")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertNear(actual, expected, tolerance, message)
  if math.abs(actual - expected) > (tolerance or 0.000001) then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function pokemon(id, species, seed, family)
  local entity = Entity.newWildPokemon({
    id = id,
    species = species,
    level = 5,
    personalitySeed = seed,
    home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = seed, spawnY = 1 }
  })
  entity.ecology.family = family
  return entity
end

local function firstContact(observer, subject, distance, tick)
  Social.observeNearby(observer, subject.id, distance, tick, subject)
  return Perception.observe(observer, {
    { name = Perception.EVENTS.ENTITY_SEEN, targetEntityId = subject.id },
    distance <= 2 and { name = Perception.EVENTS.ENTITY_NEAR,
      targetEntityId = subject.id } or nil
  }, tick)
end

local pokemonA = pokemon("wild:route-test:0001", "PIDGEY", 1, "A")
local pokemonB = pokemon("wild:route-test:0002", "PIDGEY", 2, "A")
local pokemonC = pokemon("wild:route-test:0003", "RATTATA", 3, "C")

-- Merely sharing a persistent route population creates no pair records.
local routePopulation = { pokemonA, pokemonB, pokemonC }
for _ = 1, 300 do
  for _, observer in ipairs(routePopulation) do
    Perception.observe(observer, {}, 1)
  end
end
assertEquals(pokemonA.relationships[pokemonB.id], nil,
  "no contact must not allocate A -> B")
assertEquals(pokemonB.relationships[pokemonA.id], nil,
  "no contact must not allocate B -> A")

local mutations = {}
Relationships.setMutationSink(function(mutation)
  mutations[#mutations + 1] = mutation
end)

-- A independently perceives B. The producer direction is observer -> subject.
firstContact(pokemonA, pokemonB, 2, 10)
local aToB = pokemonA.relationships[pokemonB.id]
assertTrue(aToB ~= nil, "first meaningful contact should create A -> B")
assertEquals(pokemonB.relationships[pokemonA.id], nil,
  "A observing B must not mirror B -> A")
assertTrue(aToB.familiarity > 0 and aToB.affinity > 0,
  "nearby contact should update familiarity and affinity")
assertEquals(mutations[1].observerId, pokemonA.id,
  "mutation trace should retain observer direction")
assertEquals(mutations[1].subjectId, pokemonB.id,
  "mutation trace should retain subject direction")
assertEquals(mutations[1].event, "SOCIAL_NEARBY",
  "the first production mutation should identify nearby social contact")

-- Reverse observation is independent and does not alias A's record.
firstContact(pokemonB, pokemonA, 5, 11)
local bToA = pokemonB.relationships[pokemonA.id]
assertTrue(bToA ~= nil and bToA ~= aToB,
  "reverse contact should create an independent B -> A record")
assertTrue(aToB.affinity > bToA.affinity,
  "asymmetric contact distance should produce materially different records")
local bFamiliarityBefore = bToA.familiarity

-- Repeated ordinary contact exposes the current progression without invented gains.
local progression = { aToB.familiarity }
for encounter = 1, 3 do
  firstContact(pokemonA, pokemonB, 2, 20 + encounter)
  progression[#progression + 1] = aToB.familiarity
end
assertTrue(progression[1] < progression[2]
  and progression[2] < progression[3]
  and progression[3] < progression[4],
  "repeated contact should monotonically accumulate A -> B familiarity")
assertEquals(bToA.familiarity, bFamiliarityBefore,
  "A's repeated observations must not mutate B -> A")

-- Different-species storage uses the same relationship representation.
firstContact(pokemonA, pokemonC, 2, 30)
local aToC = pokemonA.relationships[pokemonC.id]
assertTrue(aToC ~= nil and type(aToC.directThreatMemory) == "number",
  "different-species contact should use the generic relationship record")
assertTrue(aToC.familiarity > 0 and aToC.affinity > 0,
  "different-species contact should remain a valid producer")

-- Group identity alone remains separate from relationships.
local groupedLeft = pokemon("wild:group:left", "PIDGEY", 4, "A")
local groupedRight = pokemon("wild:group:right", "PIDGEY", 5, "A")
groupedLeft.groupId = "flock:one"
groupedRight.groupId = "flock:one"
assertEquals(groupedLeft.relationships[groupedRight.id], nil,
  "shared group membership must not imply relationship allocation")

-- Direct attack writes only victim -> aggressor direct provenance.
local victim = pokemon("wild:victim", "PIDGEY", 6, "A")
local aggressor = pokemon("wild:aggressor", "RATTATA", 7, "C")
Perception.observe(victim, {
  { name = Perception.EVENTS.ENTITY_ATTACKED,
    targetEntityId = aggressor.id, threatDelta = 4 }
}, 40)
local victimMemory = victim.relationships[aggressor.id]
assertEquals(victimMemory.threatMemory, 4,
  "direct attack should raise victim general threat memory")
assertEquals(victimMemory.directThreatMemory, 4,
  "direct attack should raise victim direct-threat provenance")
assertEquals(aggressor.relationships[victim.id], nil,
  "victim threat memory must not mirror onto the aggressor")
assertEquals(victim.runtimeState.directThreatEvidence[aggressor.id].reason,
  "ENTITY_ATTACKED", "direct evidence should retain authoritative provenance")

-- Social alarm is transient and cannot fabricate relationship/direct identity.
local alarmObserver = pokemon("wild:alarm-observer", "PIDGEY", 8, "A")
Fear.update(alarmObserver, {
  socialSources = {
    { id = pokemonB.id, species = pokemonB.species, ecology = pokemonB.ecology,
      alarmOutput = 0.9, alarmGroundedness = 1, state = "FLEE", distance = 1,
      escapeBias = { dx = 1, dy = 0 } }
  },
  perceptionRadius = 5
}, 41)
assertEquals(alarmObserver.relationships[pokemonB.id], nil,
  "social alarm alone must not create a relationship")
assertEquals(alarmObserver.runtimeState.directThreatId, nil,
  "social alarm must not fabricate direct threat identity")

-- One real production consumer must react to the observer's directed record.
local chooser = pokemon("wild:chooser", "PIDGEY", 9, "A")
chooser.temperament.curiosity = 0.5
local lowRel = Relationships.getOrCreate(chooser, pokemonB.id)
local rivalRel = Relationships.getOrCreate(chooser, pokemonC.id)
lowRel.trust, lowRel.affinity = 0, 0
rivalRel.trust, rivalRel.affinity = 20, 10
local candidates = {
  { id = pokemonB.id, distance = 2, novelty = 0 },
  { id = pokemonC.id, distance = 2, novelty = 0 }
}
local lowTarget, lowScore = TargetSelector.choose(chooser, candidates,
  { behavior = "APPROACH" })
assertTrue(lowTarget ~= nil, "low-relationship scenario should select a target")
local lowTargetId = lowTarget and lowTarget.id or nil
assertEquals(lowTargetId, pokemonC.id,
  "low A -> B relationship should lose approach target ranking")
lowRel.trust, lowRel.affinity = 80, 60
local highTarget, highScore = TargetSelector.choose(chooser, candidates,
  { behavior = "APPROACH" })
assertTrue(highTarget ~= nil, "high-relationship scenario should select a target")
local highTargetId = highTarget and highTarget.id or nil
assertEquals(highTargetId, pokemonB.id,
  "high A -> B relationship should win approach target ranking")
assertTrue(highScore > lowScore,
  "relationship-only change should measurably raise selected approach score")
local lowUtility = Utility.scoreBehaviors(chooser,
  { familiarity = 0, trust = 0, affinity = 0 },
  { hasTarget = true, purposefulTarget = true, distance = 2,
    conspecific = true, currentFear = 0, allowTargeting = false })
local highUtility = Utility.scoreBehaviors(chooser, lowRel,
  { hasTarget = true, purposefulTarget = true, distance = 2,
    conspecific = true, currentFear = 0, allowTargeting = false })
assertTrue(highUtility.APPROACH > lowUtility.APPROACH,
  "directed relationship should affect production APPROACH utility")

-- Player and Pokemon targets share the same generic API and shape.
local playerRel = Relationships.getOrCreate(chooser, "player")
for _, field in ipairs({ "familiarity", "trust", "affinity", "threatMemory",
  "directThreatMemory", "hostility", "lastSeenTick", "importance" }) do
  assertEquals(type(playerRel[field]), type(lowRel[field]),
    "player and Pokemon relationship API should share field " .. field)
end

-- Runtime reset preserves persistent identity/data and clears transient state.
local persistentRelationship = pokemonA.relationships[pokemonB.id]
pokemonA.runtimeState = {
  fearCurrent = 0.9,
  targetEntityId = pokemonB.id,
  movementRequest = { direction = "RIGHT" },
  perceivedFear = { [pokemonB.id] = 3 }
}
RuntimeState.reset(pokemonA)
assertEquals(pokemonA.id, "wild:route-test:0001",
  "runtime reset should preserve persistent ID")
assertEquals(pokemonA.relationships[pokemonB.id], persistentRelationship,
  "runtime reset should preserve directed relationship object")
assertEquals(pokemonA.runtimeState.fearCurrent, nil,
  "runtime reset should clear transient Fear")
assertEquals(pokemonA.runtimeState.targetEntityId, nil,
  "runtime reset should clear transient targets")
assertEquals(pokemonA.runtimeState.movementRequest, nil,
  "runtime reset should clear movement requests")

-- Non-selected/rematerialized individuals retain identity-owned data in the pool.
local persistentMembers = {
  [pokemonA.id] = pokemonA,
  [pokemonB.id] = pokemonB,
  [pokemonC.id] = pokemonC
}
local selectedVisit = { pokemonA.id, pokemonC.id }
assertEquals(persistentMembers[pokemonA.id].relationships[pokemonB.id],
  persistentRelationship,
  "relationship to a non-selected individual should remain in population data")
selectedVisit = { pokemonA.id, pokemonB.id }
assertEquals(persistentMembers[selectedVisit[2]].id, pokemonB.id,
  "later rematerialization should reuse B's persistent ID")
assertEquals(persistentMembers[pokemonA.id].relationships[pokemonB.id],
  persistentRelationship,
  "later B appearance must not recreate A -> B from zero")

-- Sparse scaling: only explicitly interacting observers allocate records.
local sparsePopulation = {}
for index = 1, 20 do
  sparsePopulation[index] = pokemon("wild:sparse:" .. index,
    index % 2 == 0 and "PIDGEY" or "RATTATA", 100 + index,
    index % 2 == 0 and "A" or "C")
end
firstContact(sparsePopulation[1], sparsePopulation[2], 2, 100)
firstContact(sparsePopulation[3], sparsePopulation[4], 2, 101)
local actualRecords = 0
for _, entity in ipairs(sparsePopulation) do
  for _ in pairs(entity.relationships) do actualRecords = actualRecords + 1 end
end
assertEquals(actualRecords, 2,
  "20 entities should allocate only the two meaningful directed contacts")
assertTrue(actualRecords < 20 * 19,
  "relationship storage must remain sparse rather than N squared")
for _, mutation in ipairs(mutations) do
  assertTrue(#mutation.changes > 0,
    "relationship diagnostics must suppress unchanged events")
  for _, change in ipairs(mutation.changes) do
    assertTrue(change.old ~= change.new,
      "relationship diagnostics must include only changed fields")
  end
end

Relationships.setMutationSink(nil)
print(string.format(
  "INTER_POKEMON_RELATIONSHIPS progression=%.2f,%.2f,%.2f,%.2f attack=%s/%s lowTarget=%s lowScore=%.2f highTarget=%s highScore=%.2f population=20 possiblePairs=380 actualRecords=%d mutations=%d",
  progression[1], progression[2], progression[3], progression[4],
  tostring(victimMemory.threatMemory), tostring(victimMemory.directThreatMemory),
  tostring(lowTargetId), lowScore, tostring(highTargetId), highScore,
  actualRecords, #mutations))

return true
