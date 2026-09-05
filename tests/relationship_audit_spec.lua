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

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function pokemon(index)
  local entity = Entity.newWildPokemon({
    id = string.format("wild:route-test:%04d", index),
    species = "PIDGEY",
    level = 5,
    personalitySeed = index,
    home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = index, spawnY = 1 }
  })
  entity.ecology.family = "BIRD"
  return entity
end

local writes = {}
local audit = RelationshipAudit.new({
  writer = function(key, bytes) writes[key] = bytes end
})
Relationships.setMutationSink(function(mutation) audit:observe(mutation) end)

local pokemonA = pokemon(1)
local pokemonB = pokemon(2)
Social.observeNearby(pokemonA, pokemonB.id, 2, 1, pokemonB)
Social.observeNearby(pokemonA, pokemonB.id, 2, 2, pokemonB)
local initial = audit:snapshot()
assertEquals(initial.relationshipAuditCreationRecords, 1,
  "first contact should emit one creation record")
assertEquals(initial.relationshipAuditRecordsWritten, 1,
  "routine second contact should be coalesced")
assertEquals(pokemonB.relationships[pokemonA.id], nil,
  "A to B auditing must not create B to A state")

Relationships.applyPerceptionEvent(pokemonA, pokemonB.id, "ENTITY_ATTACKED",
  { threatDelta = 4 }, 3)
local afterAttack = audit:snapshot()
assertEquals(afterAttack.relationshipAuditThreatRecords, 1,
  "direct attack should emit immediately")
assertEquals(afterAttack.relationshipAuditRecordsWritten, 2,
  "direct attack should add one compact multi-field record")

local tinyWrites = {}
local rotating = RelationshipAudit.new({
  maxBytes = 400,
  writer = function(key, bytes) tinyWrites[key] = bytes end
})
for index = 1, 4 do
  rotating:observe({
    observerId = "observer",
    subjectId = "subject-" .. index,
    event = "SOCIAL_NEARBY",
    tick = index,
    created = true,
    relationship = { familiarity = index }
  })
end
assertTrue(rotating:flush(30, true), "rotating audit should flush")
local rotationSnapshot = rotating:snapshot()
assertTrue(rotationSnapshot.relationshipAuditFileCount > 1,
  "overflow should create numbered files")
assertTrue(tinyWrites.relationship_audit ~= nil,
  "first file should use the unsuffixed key")
assertTrue(tinyWrites.relationship_audit_2 ~= nil,
  "second file should use the _2 key")
for key, bytes in pairs(tinyWrites) do
  assertTrue(#bytes <= 400, key .. " must remain within its cap")
end
assertEquals(rotationSnapshot.relationshipAuditDroppedRecords, 0,
  "normal rotation should not drop records")
local priorSequence = 0
local recoveredRecords = 0
for index = 1, rotationSnapshot.relationshipAuditFileCount do
  local key = index == 1 and "relationship_audit"
    or "relationship_audit_" .. tostring(index)
  for line in tinyWrites[key]:gmatch("[^\n]+") do
    local sequence = tonumber(line:match("seq=(%d+)")) or -1
    assertTrue(sequence > priorSequence,
      "relationship rollover sequences should remain monotonic")
    priorSequence = sequence
    recoveredRecords = recoveredRecords + 1
  end
end
assertEquals(recoveredRecords, 4,
  "relationship rollover should preserve each record exactly once")

local writerAttempts = 0
local failing = RelationshipAudit.new({
  writer = function()
    writerAttempts = writerAttempts + 1
    if writerAttempts < 3 then error("simulated storage failure") end
  end
})
failing:observe({
  observerId = "a", subjectId = "b", event = "SOCIAL_NEARBY", tick = 1,
  created = true, relationship = { familiarity = 1 }
})
assertEquals(failing:flush(30, true), false, "first failed write should fail soft")
assertEquals(failing:flush(60, true), false, "repeated failed write should fail soft")
assertEquals(failing:snapshot().relationshipAuditWriteFailures, 1,
  "one failure episode should not spam diagnostics")
assertEquals(failing:flush(90, true), true, "dirty data should retry successfully")

-- Smooth development emits only semantic bands, never accumulated 5-point deltas.
local milestoneWrites = {}
local milestones = RelationshipAudit.new({
  writer = function(key, bytes) milestoneWrites[key] = bytes end
})
local milestoneValues = {
  familiarity = 0, trust = 0, affinity = 18.7, threatMemory = 0,
  directThreatMemory = 0, hostility = 0
}
local function observeFamiliarity(value, tick, created)
  local before = {}
  for key, current in pairs(milestoneValues) do before[key] = current end
  milestoneValues.familiarity = value
  milestones:observe({
    observerId = "journal-a", subjectId = "journal-b",
    event = "SOCIAL_NEARBY", tick = tick, created = created == true,
    before = before, relationship = milestoneValues
  })
end
observeFamiliarity(0, 1, true)
for tick, value in ipairs({ 5, 9, 10.2, 15, 24, 25.3, 31, 49, 50.2 }) do
  observeFamiliarity(value, tick + 1, false)
end
assertTrue(milestones:flush(20, true), "semantic milestones should flush")
local milestoneText = milestoneWrites.relationship_audit
assertEquals(select(2, milestoneText:gsub("type=FAMILIARITY_MILESTONE", "")),
  3, "familiarity should journal only 10, 25, and 50 crossings")
assertTrue(milestoneText:find("thresholds=10", 1, true) ~= nil,
  "10 should be a coarse historical milestone")
assertTrue(milestoneText:find("thresholds=25", 1, true) ~= nil,
  "25 should be a coarse historical milestone")
assertTrue(milestoneText:find("thresholds=50", 1, true) ~= nil,
  "50 should be a coarse historical milestone")
assertTrue(not milestoneText:find("5->", 1, true),
  "semantic milestones must not render audit baselines as mutations")
assertTrue(milestoneText:find("familiarity=25.3", 1, true) ~= nil
    and milestoneText:find("affinity=18.7", 1, true) ~= nil,
  "milestones should contain exact canonical current values")

local jumpWrites = {}
local jump = RelationshipAudit.new({
  writer = function(key, bytes) jumpWrites[key] = bytes end
})
jump:observe({
  observerId = "jump-a", subjectId = "jump-b", event = "TEST_JUMP",
  tick = 1,
  before = { familiarity = 8 },
  relationship = { familiarity = 27 }
})
jump:flush(1, true)
assertTrue(jumpWrites.relationship_audit:find("thresholds=10,25", 1, true),
  "one field jump should combine multiple crossed thresholds")

local soakWrites = {}
local soak = RelationshipAudit.new({
  maxBytes = 196 * 1024,
  writer = function(key, bytes) soakWrites[key] = bytes end
})
local consequentialMutationCount = 0
Relationships.setMutationSink(function(mutation)
  consequentialMutationCount = consequentialMutationCount + 1
  soak:observe(mutation)
end)
local population = {}
for index = 1, 20 do population[index] = pokemon(index) end
local contactCallCount = 0
for tick = 15, 10000, 15 do
  for observerIndex, observer in ipairs(population) do
    for offset = 1, 2 do
      local subjectIndex = ((observerIndex - 1 + offset) % #population) + 1
      Social.observeNearby(observer, population[subjectIndex].id, 2, tick,
        population[subjectIndex])
      contactCallCount = contactCallCount + 1
    end
  end
end
assertTrue(soak:flush(10000, true), "10,000-tick soak should flush")
local soakSnapshot = soak:snapshot()
assertEquals(contactCallCount, 26640, "soak should exercise expected contact volume")
assertTrue(consequentialMutationCount < contactCallCount / 5,
  "bounded exposure should avoid lifecycle-level relationship mutations")
assertEquals(soakSnapshot.relationshipAuditFileCount, 1,
  "first 196 KiB file must hold at least five minutes")
assertTrue(#soakWrites.relationship_audit <= 196 * 1024,
  "five-minute output must fit the first file")
assertTrue(soakSnapshot.relationshipAuditMinorUpdatesSuppressed > 2500,
  "routine peaceful updates should be semantically suppressed")
assertTrue(soakSnapshot.relationshipAuditRecordsWritten < 700,
  "semantic journal should remain bounded across relationship lifetimes")
assertEquals(soakSnapshot.relationshipAuditWriteCalls, 1,
  "one final flush should perform one storage write")

print(string.format(
  "RELATIONSHIP_AUDIT_SOAK ticks=10000 contactCalls=%d mutations=%d records=%d suppressed=%d ioBytes=%d bufferedBytes=%d writes=%d cap=%d files=%d",
  contactCallCount,
  consequentialMutationCount,
  soakSnapshot.relationshipAuditRecordsWritten,
  soakSnapshot.relationshipAuditMinorUpdatesSuppressed,
  soakSnapshot.relationshipAuditBytesWritten,
  #soakWrites.relationship_audit,
  soakSnapshot.relationshipAuditWriteCalls,
  soakSnapshot.relationshipAuditMaxBytes,
  soakSnapshot.relationshipAuditFileCount))

Relationships.setMutationSink(nil)
