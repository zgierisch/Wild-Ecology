local Entity = require("src.entities.entity")
local Perception = require("src.world.perception")
local Relationships = require("src.entities.relationships")
local Social = require("src.behavior.social")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function pokemon(id, seed)
  return Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 5,
    personalitySeed = seed,
    home = {
      mapId = "ROUTE_CONTACT_TEST",
      zoneId = "contact-test",
      spawnX = seed,
      spawnY = 1
    }
  })
end

local function runContinuousContact(ticks)
  local observer = pokemon("wild:contact:observer:" .. ticks, 1)
  local subject = pokemon("wild:contact:subject:" .. ticks, 2)
  local report = {
    calls = { SOCIAL_NEARBY = 0, ENTITY_NEAR = 0, ENTITY_SEEN = 0 },
    events = {},
    familiarityByEvent = {},
    affinityByEvent = {},
    thresholds = { familiarity = {}, affinity = {} },
    valuesByTick = {},
    relationshipMutations = 0
  }
  local thresholds = { 10, 25, 50, 75, 100 }

  Relationships.setMutationSink(function(mutation)
    report.relationshipMutations = report.relationshipMutations + 1
    local event = mutation.event
    report.events[event] = (report.events[event] or 0) + 1
    report.familiarityByEvent[event] = (report.familiarityByEvent[event] or 0)
      + ((mutation.relationship.familiarity or 0)
        - (mutation.before.familiarity or 0))
    report.affinityByEvent[event] = (report.affinityByEvent[event] or 0)
      + ((mutation.relationship.affinity or 0)
        - (mutation.before.affinity or 0))
  end)
  Social.setContactSink(function(contact)
    report.contactObservations = (report.contactObservations or 0) + 1
    if contact.newEpisode then
      report.contactEpisodes = (report.contactEpisodes or 0) + 1
    end
    if contact.exposureApplied then
      report.contactExposures = (report.contactExposures or 0) + 1
    end
  end)

  for tick = 1, ticks do
    report.calls.SOCIAL_NEARBY = report.calls.SOCIAL_NEARBY + 1
    Social.observeNearby(observer, subject.id, 2, tick, subject)
    local observations = {}
    if tick == 1 then
      report.calls.ENTITY_SEEN = report.calls.ENTITY_SEEN + 1
      observations[#observations + 1] = {
        name = Perception.EVENTS.ENTITY_SEEN,
        targetEntityId = subject.id
      }
    end
    observations[#observations + 1] = {
      name = Perception.EVENTS.ENTITY_NEAR,
      targetEntityId = subject.id
    }
    report.calls.ENTITY_NEAR = report.calls.ENTITY_NEAR + 1
    Perception.observe(observer, observations, tick)

    local relationship = observer.relationships[subject.id]
    report.valuesByTick[tick] = {
      familiarity = relationship.familiarity,
      affinity = relationship.affinity,
      trust = relationship.trust
    }
    for _, threshold in ipairs(thresholds) do
      if not report.thresholds.familiarity[threshold]
        and relationship.familiarity >= threshold then
        report.thresholds.familiarity[threshold] = tick
      end
      if not report.thresholds.affinity[threshold]
        and relationship.affinity >= threshold then
        report.thresholds.affinity[threshold] = tick
      end
    end
  end
  Relationships.setMutationSink(nil)
  Social.setContactSink(nil)
  report.relationship = observer.relationships[subject.id]
  return report
end

local twenty = runContinuousContact(20)
assertEquals(twenty.calls.SOCIAL_NEARBY, 20,
  "baseline SOCIAL_NEARBY should be lifecycle-level")
assertEquals(twenty.calls.ENTITY_NEAR, 20,
  "baseline ENTITY_NEAR should be lifecycle-level")
assertEquals(twenty.calls.ENTITY_SEEN, 1,
  "ENTITY_SEEN should remain an entry edge")

local baseline = runContinuousContact(500)
assertEquals(baseline.calls.SOCIAL_NEARBY, 500,
  "baseline should expose repeated social contact")
assertEquals(baseline.calls.ENTITY_NEAR, 500,
  "baseline should expose repeated near perception")
assertEquals(baseline.relationship.trust, 0,
  "peaceful Pokemon contact must not synthesize trust")
assertEquals(baseline.contactObservations, 500,
  "continuous contact should still be observed every lifecycle tick")
assertEquals(baseline.contactEpisodes, 1,
  "continuous contact should remain one production episode")
assertEquals(baseline.contactExposures, 5,
  "continuous contact should apply bounded exposure every 100 ticks")
assertEquals(baseline.events.SOCIAL_NEARBY, 5,
  "SOCIAL_NEARBY should identify meaningful bounded exposure")
assertEquals(baseline.events.ENTITY_NEAR, nil,
  "ENTITY_NEAR should not duplicate relationship growth")
assertEquals(baseline.relationshipMutations, 6,
  "five social exposures plus first sight should be consequential")
assertEquals(baseline.valuesByTick[50].familiarity, 2.875,
  "first 50 ticks should contain one social exposure plus first sight")
assertEquals(baseline.valuesByTick[100].familiarity, 2.875,
  "exposure should not repeat before the bounded interval")
assertEquals(baseline.valuesByTick[500].familiarity, 10.375,
  "500 ticks should contain five bounded social exposures")
assertEquals(baseline.valuesByTick[500].affinity, 9.375,
  "affinity should grow through bounded social exposure")
assertEquals(baseline.valuesByTick[200].affinity
    - baseline.valuesByTick[100].affinity, 1.875,
  "second 100 ticks should apply one existing exposure gain")
assertEquals(baseline.valuesByTick[300].affinity
    - baseline.valuesByTick[200].affinity, 1.875,
  "third 100 ticks should apply one existing exposure gain")
assertEquals(baseline.valuesByTick[400].affinity
    - baseline.valuesByTick[300].affinity, 1.875,
  "fourth 100 ticks should apply one existing exposure gain")
assertEquals(baseline.valuesByTick[500].affinity
    - baseline.valuesByTick[400].affinity, 1.875,
  "fifth 100 ticks should apply one existing exposure gain")

-- A later encounter is distinct and can develop the relationship immediately.
local encounterA = pokemon("wild:encounter:a", 3)
local encounterB = pokemon("wild:encounter:b", 4)
local episodeStarts = 0
Social.setContactSink(function(contact)
  if contact.newEpisode then episodeStarts = episodeStarts + 1 end
end)
for tick = 1, 100 do
  Social.observeNearby(encounterA, encounterB.id, 2, tick, encounterB)
end
local firstEncounterAffinity = encounterA.relationships[encounterB.id].affinity
for tick = 132, 231 do
  Social.observeNearby(encounterA, encounterB.id, 2, tick, encounterB)
end
Social.setContactSink(nil)
assertEquals(episodeStarts, 2,
  "meaningful separation should produce two contact episodes")
assertEquals(encounterA.relationships[encounterB.id].affinity
    > firstEncounterAffinity, true,
  "re-encounter should produce immediate additional development")

-- Pair-local runtime cadence must not suppress another directed subject.
local multiA = pokemon("wild:multi:a", 5)
local multiB = pokemon("wild:multi:b", 6)
local multiC = pokemon("wild:multi:c", 7)
Social.observeNearby(multiA, multiB.id, 2, 1, multiB)
Social.observeNearby(multiA, multiC.id, 2, 1, multiC)
Social.observeNearby(multiB, multiC.id, 2, 1, multiC)
assertEquals(multiA.relationships[multiB.id].affinity > 0, true,
  "A to B should receive its own exposure")
assertEquals(multiA.relationships[multiC.id].affinity > 0, true,
  "A to C should receive its own exposure")
assertEquals(multiB.relationships[multiC.id].affinity > 0, true,
  "B to C should receive its own exposure")
assertEquals(multiB.relationships[multiA.id], nil,
  "directed contact must not fabricate reverse history")

-- Peaceful cadence cannot throttle an authoritative direct threat.
Relationships.applyPerceptionEvent(multiA, multiB.id, "ENTITY_ATTACKED",
  { threatDelta = 4 }, 2)
assertEquals(multiA.relationships[multiB.id].directThreatMemory, 4,
  "direct threat memory should remain immediate during contact")

-- Runtime reconstruction ends an episode without persisting telemetry state.
local durableRelationship = multiA.relationships[multiB.id]
multiA.runtimeState = nil
Social.observeNearby(multiA, multiB.id, 2, 3, multiB)
assertEquals(multiA.relationships[multiB.id], durableRelationship,
  "runtime reconstruction should retain canonical relationship identity")
assertEquals(multiA.runtimeState.relationshipContacts[multiB.id].episodeId, 1,
  "runtime reconstruction should begin a fresh transient episode")

local function thresholdList(values)
  local parts = {}
  for _, threshold in ipairs({ 10, 25, 50, 75, 100 }) do
    parts[#parts + 1] = threshold .. ":" .. tostring(values[threshold] or ">500")
  end
  return table.concat(parts, ",")
end

print(string.format(
  "CONTACT_AFTER ticks=500 socialCalls=%d nearCalls=%d seenCalls=%d mutations=%d "
    .. "familiarity=%g affinity=%g trust=%g famThresholds=%s affThresholds=%s "
    .. "twentySocialFam=%g twentyNearFam=%g twentySocialAffinity=%g twentyNearAffinity=%g",
  baseline.calls.SOCIAL_NEARBY,
  baseline.calls.ENTITY_NEAR,
  baseline.calls.ENTITY_SEEN,
  baseline.relationshipMutations,
  baseline.relationship.familiarity,
  baseline.relationship.affinity,
  baseline.relationship.trust,
  thresholdList(baseline.thresholds.familiarity),
  thresholdList(baseline.thresholds.affinity),
  twenty.familiarityByEvent.SOCIAL_NEARBY or 0,
  twenty.familiarityByEvent.ENTITY_NEAR or 0,
  twenty.affinityByEvent.SOCIAL_NEARBY or 0,
  twenty.affinityByEvent.ENTITY_NEAR or 0
))
print("CONTACT_BEFORE ticks=500 socialCalls=500 nearCalls=500 seenCalls=1 "
  .. "mutations=535 familiarity50=100 familiarity100=100 familiarity500=100 "
  .. "affinity50=93.75 affinity100=100 affinity500=100 "
  .. "familiarity100Tick=35 affinity100Tick=54")

return true
