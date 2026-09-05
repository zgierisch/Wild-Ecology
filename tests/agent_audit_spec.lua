local AgentAudit = require("src.debug.agent_audit")
local Controller = require("src.behavior.controller")
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

local function pokemon(id, seed)
  local entity = Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 5,
    personalitySeed = seed,
    home = { mapId = "ROUTE_TEST", zoneId = "test", spawnX = seed, spawnY = 1 }
  })
  entity.ecology.family = "BIRD"
  entity.runtimeState = entity.runtimeState or { state = "IDLE" }
  return entity
end

local writes = {}
local entities = {}
local function contextFor(mutation)
  local observer = entities[mutation.observerId]
  local subject = entities[mutation.subjectId]
  return {
    observer = {
      id = mutation.observerId,
      persistentId = mutation.observerId,
      species = observer and observer.species,
      kind = observer and "POKEMON",
      map = "ROUTE_TEST",
      cellX = 1,
      cellY = 1,
      behavior = observer and observer.runtimeState and observer.runtimeState.state,
      previousBehavior = mutation.diagnosticContext
        and mutation.diagnosticContext.previousBehaviorState,
      targetEntityId = observer and observer.runtimeState
        and observer.runtimeState.targetEntityId,
      fearCurrent = observer and observer.runtimeState
        and observer.runtimeState.fearCurrent,
      groupId = observer and observer.ecology and observer.ecology.family
    },
    subject = {
      id = mutation.subjectId,
      persistentId = mutation.subjectId,
      species = subject and subject.species,
      kind = subject and "POKEMON",
      map = "ROUTE_TEST",
      cellX = 2,
      cellY = 1,
      behavior = subject and subject.runtimeState and subject.runtimeState.state,
      groupId = subject and subject.ecology and subject.ecology.family
    },
    distance = 1,
    sameGroup = true,
    sameSpecies = true,
    socialCompatibility = 1
  }
end

local audit = AgentAudit.new({
  writer = function(key, bytes) writes[key] = bytes end,
  contextProvider = contextFor,
  separationTicks = 30,
  periodicTicks = 300
})
Relationships.setMutationSink(function(mutation) audit:observeMutation(mutation) end)
Relationships.setDiagnosticSink(function(event) audit:observeEvent(event) end)
Social.setContactSink(function(contact) audit:observeContact(contact) end)

local pokemonA = pokemon("wild:test:0001", 1)
local pokemonB = pokemon("wild:test:0002", 2)
entities[pokemonA.id] = pokemonA
entities[pokemonB.id] = pokemonB

-- One uninterrupted contact episode uses bounded exposure and stays active.
local saturationTick = nil
local affinitySaturationTick = nil
for tick = 1, 400 do
  Social.observeNearby(pokemonA, pokemonB.id, 1, tick, pokemonB)
  local relationship = pokemonA.relationships[pokemonB.id]
  if not saturationTick and relationship.familiarity >= 100 then
    saturationTick = tick
  end
  if not affinitySaturationTick and relationship.affinity >= 100 then
    affinitySaturationTick = tick
  end
end
local continuous = pokemonA.relationships[pokemonB.id]
assertEquals(saturationTick, nil,
  "bounded continuous exposure should not saturate familiarity in 400 ticks")
assertEquals(affinitySaturationTick, nil,
  "bounded continuous exposure should not saturate affinity in 400 ticks")
assertEquals(continuous.familiarity, 7.5,
  "400 ticks should apply four existing social exposure gains")
assertEquals(continuous.affinity, 7.5,
  "bounded exposure should preserve the existing affinity coefficient")
assertEquals(audit:snapshot().contactEpisodesStarted, 1,
  "continuous contact should remain one diagnostic episode")
audit:sample(431, {})
assertEquals(audit:snapshot().contactEpisodesEnded, 1,
  "separation grace should close the first episode")

-- Meeting again after separation starts a distinct episode with boundary values.
Social.observeNearby(pokemonA, pokemonB.id, 1, 500, pokemonB)
audit:sample(531, {})
assertEquals(audit:snapshot().contactEpisodesStarted, 2,
  "re-meeting should start a second diagnostic episode")
assertEquals(audit:snapshot().contactEpisodesEnded, 2,
  "second separation should close the second episode")

-- Drive the real controller completion path at the suspicious high-value state.
local investigator = pokemon("wild:test:investigator", 3)
local subject = pokemon("wild:test:subject", 4)
entities[investigator.id] = investigator
entities[subject.id] = subject
local investigationRelationship = Relationships.getOrCreate(investigator, subject.id)
investigationRelationship.familiarity = 100
investigationRelationship.trust = 0
investigationRelationship.affinity = 95
local canonicalObject = investigationRelationship
investigator.runtimeState = {
  state = "INVESTIGATE",
  stateEnteredTick = 0,
  targetEntityId = subject.id
}
for tick = 90, 92 do
  audit:sample(tick, {
    [investigator.id] = {
      id = investigator.id, persistentId = investigator.id,
      species = investigator.species, kind = "POKEMON",
      map = "ROUTE_TEST", cellX = 1, cellY = 1,
      behavior = "INVESTIGATE", targetEntityId = subject.id,
      fearCurrent = 0, motionActive = false, relationshipCount = 1
    },
    [subject.id] = {
      id = subject.id, persistentId = subject.id,
      species = subject.species, kind = "POKEMON",
      map = "ROUTE_TEST", cellX = 2, cellY = 1,
      behavior = "IDLE", fearCurrent = 0,
      motionActive = false, relationshipCount = 0
    }
  })
end
Controller.tick(investigator, investigationRelationship, 2, {
  hasTarget = true,
  purposefulTarget = true,
  targetEntityId = subject.id,
  targetCandidates = {
    { id = subject.id, distance = 2, novelty = 0 }
  },
  position = { cellX = 1, cellY = 1 },
  targetPositions = {
    [subject.id] = { cellX = 2, cellY = 1 }
  }
}, 100)
assertEquals(investigator.relationships[subject.id], canonicalObject,
  "INVESTIGATION_COMPLETED must retain the canonical relationship object")
assertEquals(canonicalObject.familiarity, 100,
  "INVESTIGATION_COMPLETED must not reset saturated familiarity")
assertEquals(canonicalObject.trust, 0,
  "INVESTIGATION_COMPLETED must not synthesize trust")
assertEquals(canonicalObject.affinity, 95,
  "INVESTIGATION_COMPLETED must not reset affinity")
local investigationPost = {
  familiarity = canonicalObject.familiarity,
  trust = canonicalObject.trust,
  affinity = canonicalObject.affinity
}
Social.observeNearby(investigator, subject.id, 1, 101, subject)

-- Direct threat context remains authoritative and directed.
Relationships.applyPerceptionEvent(investigator, subject.id, "ENTITY_ATTACKED",
  { threatDelta = 4 }, 102)
assertEquals(canonicalObject.directThreatMemory, 4,
  "direct attack should retain its real direct-threat mutation")
assertEquals(subject.relationships[investigator.id], nil,
  "directed diagnostics must not create reverse relationship state")
Social.observeNearby(subject, investigator.id, 1, 102, investigator)
assertTrue(subject.relationships[investigator.id] ~= nil,
  "a real reverse event should create an independent directed relationship")
assertTrue(subject.relationships[investigator.id] ~= canonicalObject,
  "reverse relationship identity must be independent")
audit:sample(140, {})
assertEquals(audit:snapshot().contactEpisodesStarted, 3,
  "bidirectional observation should create one physical pair episode")
assertEquals(audit:snapshot().contactEpisodesEnded, 3,
  "the physical investigator/subject episode should end once")

-- Deliberate test-only replacement must be detected on the next real producer.
investigator.relationships[subject.id] = {
  familiarity = 25, trust = 5, affinity = 10, threatMemory = 0,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 102,
  importance = 0.2
}
Relationships.applyPerceptionEvent(investigator, subject.id, "ENTITY_SEEN",
  {}, 103)
assertEquals(audit:snapshot().objectReplacements, 1,
  "canonical object replacement should emit an anomaly")

-- Coalescer baseline and canonical current state remain separately labeled.
local comparisonWrites = {}
local comparison = AgentAudit.new({
  writer = function(key, bytes) comparisonWrites[key] = bytes end,
  contextProvider = contextFor
})
local coalescer = RelationshipAudit.new({ writer = function() end })
local comparisonActor = pokemon("wild:test:compare-a", 5)
local comparisonSubject = pokemon("wild:test:compare-b", 6)
entities[comparisonActor.id] = comparisonActor
entities[comparisonSubject.id] = comparisonSubject
Relationships.setMutationSink(function(mutation)
  local _, emission = coalescer:observe(mutation)
  comparison:observeMutation(mutation, emission)
end)
Social.setContactSink(function(contact) comparison:observeContact(contact) end)
for tick = 1, 20 do
  Social.observeNearby(comparisonActor, comparisonSubject.id, 1, tick,
    comparisonSubject)
end
assertTrue(comparison:flush(30, true), "comparison audit should flush")
assertTrue(not comparisonWrites.agent_audit:find(
    "RELATIONSHIP_AUDIT_CROSSREF", 1, true),
  "light mode should suppress routine coalescer cross-references")
assertEquals(comparison:snapshot().auditMismatches, 0,
  "expected coalescing differences must not be called canonical mismatches")

local anomalyRelationship = {
  familiarity = 40, trust = 10, affinity = 20, threatMemory = 0,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 200
}
comparison:observeMutation({
  observerId = comparisonActor.id,
  subjectId = comparisonSubject.id,
  event = "TEST_DECREASE",
  producer = "tests.agent_audit_spec",
  tick = 200,
  before = {
    familiarity = 80, trust = 10, affinity = 20, threatMemory = 0,
    directThreatMemory = 0, hostility = 0, lastSeenTick = 199
  },
  relationship = anomalyRelationship,
  relationshipRef = anomalyRelationship
}, {
  type = "RELATIONSHIP_MILESTONE",
  cause = "TEST_DECREASE",
  suppressedUpdates = 0,
  pendingCauses = {},
  baseline = { familiarity = 80 },
  current = { familiarity = 41 }
})
assertEquals(comparison:snapshot().largeDeltas, 1,
  "large relationship discontinuity should emit an anomaly")
assertEquals(comparison:snapshot().decreases, 1,
  "peaceful-field decrease should emit an anomaly")
assertEquals(comparison:snapshot().auditMismatches, 1,
  "coalescer current state disagreement should emit a mismatch")
local expectedFearRelationship = {
  familiarity = 0, trust = 9, affinity = 0, threatMemory = 1,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 201
}
comparison:observeMutation({
  observerId = comparisonActor.id,
  subjectId = comparisonSubject.id,
  event = "SOCIAL_FEAR",
  producer = "src.entities.relationships.applySocialFear",
  tick = 201,
  before = {
    familiarity = 0, trust = 10, affinity = 0, threatMemory = 0,
    directThreatMemory = 0, hostility = 0, lastSeenTick = 200
  },
  relationship = expectedFearRelationship,
  relationshipRef = expectedFearRelationship
})
assertEquals(comparison:snapshot().decreases, 1,
  "expected SOCIAL_FEAR trust reduction should not trigger anomaly forensics")

assertTrue(audit:flush(600, true), "agent audit should flush")
local textParts = {}
for fileIndex = 1, audit:snapshot().fileCount do
  local key = fileIndex == 1 and "agent_audit"
    or "agent_audit_" .. tostring(fileIndex)
  textParts[#textParts + 1] = writes[key] or ""
end
local text = table.concat(textParts)
for _, recordType in ipairs({
  "CONTACT_EPISODE_START", "CONTACT_EPISODE_END",
  "INVESTIGATION_COMPLETED", "RELATIONSHIP_OBJECT_REPLACED"
}) do
  assertTrue(text:find("type=" .. recordType, 1, true) ~= nil,
    "agent audit should include " .. recordType)
end
assertTrue(not text:find("type=RELATIONSHIP_MUTATION", 1, true),
  "light mode must not write routine full relationship mutations")
assertTrue(not text:find("type=RELATIONSHIP_PRE_EVENT", 1, true),
  "light mode must not write rich investigation phases")
assertTrue(not text:find("type=CONTACT_EPISODE_SAMPLE", 1, true),
  "light mode must not write periodic contact samples")
assertTrue(not text:find("type=RELATIONSHIP_CREATED", 1, true),
  "directed relationship creation belongs to relationship audit")
assertTrue(text:find("previousImportantEvent=INVESTIGATION_COMPLETED", 1, true),
  "next mutation should link to investigation completion")
assertTrue(text:find("before.familiarity=100", 1, true)
    and text:find("after.familiarity=100", 1, true),
  "compact investigation evidence should retain canonical values")
assertTrue(text:find("previousContactEpisodeEndTick=431", 1, true),
  "second episode should include the prior separation-detection tick")
assertTrue(text:find("previousContactTick=400", 1, true),
  "second episode should include the prior last-contact tick")
assertTrue(text:find("timeSincePreviousContactEpisode=69", 1, true),
  "second episode should include elapsed time since prior closure")
assertTrue(text:find("timeSincePreviousContact=100", 1, true),
  "second episode should include elapsed time since prior contact")
local physicalStartCount = select(2,
  text:gsub("type=CONTACT_EPISODE_START", ""))
assertEquals(physicalStartCount, 3,
  "three physical encounters should produce three starts, not directed pairs")
assertEquals(select(2, text:gsub("type=CONTACT_EPISODE_END", "")), 3,
  "three physical encounters should produce three ends, not directed pairs")
assertTrue(text:find("aToB.end.familiarity=", 1, true)
    and text:find("bToA.end.familiarity=", 1, true),
  "episode end should preserve both directed relationship summaries")

-- Tiny-cap rollover preserves every mutation record and strict sequence order.
local rolloverWrites = {}
local rollover = AgentAudit.new({
  maxBytes = 8000,
  writer = function(key, bytes) rolloverWrites[key] = bytes end,
  contextProvider = contextFor,
  forensicEnabled = true
})
local rolloverRelationship = {
  familiarity = 0, trust = 0, affinity = 0, threatMemory = 0,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 0
}
for index = 1, 90 do
  local before = {
    familiarity = rolloverRelationship.familiarity,
    trust = 0, affinity = 0, threatMemory = 0,
    directThreatMemory = 0, hostility = 0, lastSeenTick = index - 1
  }
  rolloverRelationship.familiarity = index
  rolloverRelationship.lastSeenTick = index
  rollover:observeMutation({
    observerId = pokemonA.id,
    subjectId = pokemonB.id,
    event = "TEST_MUTATION",
    producer = "tests.agent_audit_spec",
    tick = index,
    before = before,
    relationship = rolloverRelationship,
    relationshipRef = rolloverRelationship,
    created = index == 1
  })
end
assertTrue(rollover:flush(100, true), "rollover audit should flush")
assertTrue(rolloverWrites.agent_audit ~= nil
  and rolloverWrites.agent_audit_2 ~= nil
  and rolloverWrites.agent_audit_3 ~= nil,
  "tiny cap should produce base, _2, and _3 files")
local recoveredMutations = 0
local priorSequence = -math.huge
for fileIndex = 1, rollover:snapshot().fileCount do
  local key = fileIndex == 1 and "agent_audit"
    or "agent_audit_" .. tostring(fileIndex)
  local bytes = rolloverWrites[key]
  assertTrue(bytes ~= nil and #bytes <= 8000,
    key .. " should exist within the configured cap")
  for line in bytes:gmatch("[^\n]+") do
    local sequence = tonumber(line:match("seq=(%d+)")) or -math.huge
    assertTrue(sequence > priorSequence,
      "record sequences must increase across rollover files")
    priorSequence = sequence
    if line:find("type=RELATIONSHIP_MUTATION", 1, true) then
      recoveredMutations = recoveredMutations + 1
    end
  end
end
assertEquals(recoveredMutations, 90,
  "rollover must preserve every mutation exactly once")
assertEquals(rollover:snapshot().dropped, 0,
  "rollover must not silently drop records")

local function runAuditMode(forensicEnabled)
  local modeWrites = {}
  local recorder = AgentAudit.new({
    writer = function(key, bytes) modeWrites[key] = bytes end,
    contextProvider = contextFor,
    forensicEnabled = forensicEnabled,
    contactSampleTicks = 100
  })
  local observer = pokemon("wild:volume:observer:" .. tostring(forensicEnabled), 7)
  local subjectEntity = pokemon("wild:volume:subject:" .. tostring(forensicEnabled), 8)
  entities[observer.id] = observer
  entities[subjectEntity.id] = subjectEntity
  Relationships.setMutationSink(function(mutation)
    recorder:observeMutation(mutation)
  end)
  Social.setContactSink(function(contact) recorder:observeContact(contact) end)
  local started = os.clock()
  for tick = 1, 1000 do
    Social.observeNearby(observer, subjectEntity.id, 1, tick, subjectEntity)
    recorder:sample(tick, {})
  end
  recorder:sample(1031, {})
  recorder:flush(1031, true)
  local elapsed = os.clock() - started
  local snapshot = recorder:snapshot()
  local parts = {}
  for fileIndex = 1, snapshot.fileCount do
    local key = fileIndex == 1 and "agent_audit"
      or "agent_audit_" .. tostring(fileIndex)
    parts[#parts + 1] = modeWrites[key] or ""
  end
  return snapshot, table.concat(parts), elapsed
end

local lightSnapshot, lightText, lightSeconds = runAuditMode(false)
local forensicSnapshot, forensicText, forensicSeconds = runAuditMode(true)
assertEquals(lightSnapshot.fileCount, 1,
  "1,000-tick light audit should not roll over")
assertTrue(lightSnapshot.records < 30,
  "light audit should emit only compact high-value records")
assertTrue(lightSnapshot.bytes < 20000,
  "light audit should remain far below one rollover segment")
assertTrue(not lightText:find("type=RELATIONSHIP_MUTATION", 1, true),
  "light audit must contain no giant routine mutation records")
assertTrue(not lightText:find("type=CONTACT_EPISODE_SAMPLE", 1, true),
  "light audit must contain no routine periodic contact samples")
assertTrue(forensicText:find("type=RELATIONSHIP_MUTATION", 1, true),
  "explicit forensic mode should retain detailed mutation evidence")
assertEquals(lightSnapshot.contactObservations, 1000,
  "light audit should observe all contact without writing each observation")
assertEquals(lightSnapshot.mutations, 10,
  "1,000 ticks should apply ten bounded relationship exposures")
assertEquals(lightSnapshot.records, 2,
  "one long light encounter should write only start and end")
assertEquals(lightSnapshot.agentAuditWriteCalls, 1,
  "one final light flush should perform one storage write")

local saturated = pokemon("wild:saturated", 9)
local saturatedSubject = pokemon("wild:saturated-subject", 10)
local saturatedAudit = AgentAudit.new({ writer = function() end })
Relationships.setMutationSink(function(mutation)
  saturatedAudit:observeMutation(mutation)
end)
Social.setContactSink(function(contact)
  saturatedAudit:observeContact(contact)
end)
Social.observeNearby(saturated, saturatedSubject.id, 1, 1, saturatedSubject)
local saturatedRelationship = saturated.relationships[saturatedSubject.id]
saturatedRelationship.familiarity = 100
saturatedRelationship.affinity = 100
for tick = 2, 100 do
  Social.observeNearby(saturated, saturatedSubject.id, 1, tick,
    saturatedSubject)
end
local recordsBeforeNoOp = saturatedAudit:snapshot().records
Social.observeNearby(saturated, saturatedSubject.id, 1, 101, saturatedSubject)
assertEquals(saturatedAudit:snapshot().noOpMutations, 1,
  "saturated exposure should be counted as a consequential-field no-op")
assertEquals(saturatedAudit:snapshot().records, recordsBeforeNoOp,
  "saturated exposure should not write a light mutation or sample")

local forbiddenKeys = {
  contactEpisodeId = true,
  relationshipObjectToken = true,
  relationshipObjectId = true,
  auditCrossReference = true,
  postEventCountdown = true
}
local function assertTelemetryAbsent(value, path, seen)
  if type(value) ~= "table" then return end
  seen = seen or {}
  if seen[value] then return end
  seen[value] = true
  for key, child in pairs(value) do
    assertTrue(not forbiddenKeys[key],
      "telemetry key must not enter persistent entity shape: "
        .. tostring(path) .. "." .. tostring(key))
    assertTelemetryAbsent(child, tostring(path) .. "." .. tostring(key), seen)
  end
end
assertTelemetryAbsent(pokemonA, "pokemonA")
assertTelemetryAbsent(investigator, "investigator")

print(string.format(
  "AGENT_AUDIT continuousTicks=400 familiaritySaturationTick=%s affinitySaturationTick=%s episodes=%d investigation=%g/%g/%g objectReplacements=%d forensicRolloverFiles=%d light1000Records=%d light1000Bytes=%d light1000Files=%d lightSeconds=%.6f forensicSeconds=%.6f",
  tostring(saturationTick or ">400"),
  tostring(affinitySaturationTick or ">400"),
  audit:snapshot().contactEpisodesEnded,
  investigationPost.familiarity, investigationPost.trust,
  investigationPost.affinity,
  audit:snapshot().objectReplacements, rollover:snapshot().fileCount,
  lightSnapshot.records, lightSnapshot.bytes, lightSnapshot.fileCount,
  lightSeconds, forensicSeconds))

Relationships.setMutationSink(nil)
Relationships.setDiagnosticSink(nil)
Social.setContactSink(nil)
