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

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function pokemon(id, seed)
  local entity = Entity.newWildPokemon({
    id = id,
    species = "PIDGEY",
    level = 5,
    personalitySeed = seed,
    home = { mapId = "ROUTE_TELEMETRY", zoneId = "test",
      spawnX = seed, spawnY = 1 }
  })
  entity.ecology.family = "BIRD"
  return entity
end

local function countRecords(text, recordType)
  return select(2, (text or ""):gsub("type=" .. recordType, ""))
end

local function joinedWrites(writes, prefix, count)
  local parts = {}
  for index = 1, count do
    local key = index == 1 and prefix or prefix .. "_" .. tostring(index)
    parts[#parts + 1] = writes[key] or ""
  end
  return table.concat(parts)
end

-- Ten physical pairs, observed in both directions, remain ten episodes.
local soakWrites = {}
local soak = AgentAudit.new({
  writer = function(key, bytes) soakWrites[key] = bytes end,
  forensicEnabled = false
})
local population = {}
for index = 1, 20 do
  population[index] = pokemon("wild:soak:" .. index, index)
end
Relationships.setMutationSink(function(mutation) soak:observeMutation(mutation) end)
Social.setContactSink(function(contact) soak:observeContact(contact) end)
local soakStarted = os.clock()
for tick = 1, 10000 do
  for index = 1, 20, 2 do
    local left = population[index]
    local right = population[index + 1]
    Social.observeNearby(left, right.id, 2, tick, right)
    Social.observeNearby(right, left.id, 2, tick, left)
  end
  soak:sample(tick, {})
  soak:flush(tick, false)
end
soak:sample(10031, {})
soak:flush(10031, true)
local soakSeconds = os.clock() - soakStarted
local soakSnapshot = soak:snapshot()
local soakText = joinedWrites(soakWrites, "agent_audit", soakSnapshot.fileCount)
assertEquals(soakSnapshot.contactEpisodesStarted, 10,
  "bidirectional soak should create one physical episode per pair")
assertEquals(soakSnapshot.contactEpisodesEnded, 10,
  "bidirectional soak should end one physical episode per pair")
assertEquals(countRecords(soakText, "CONTACT_EPISODE_START"), 10,
  "light soak should write ten physical starts")
assertEquals(countRecords(soakText, "CONTACT_EPISODE_END"), 10,
  "light soak should write ten physical ends")
assertEquals(countRecords(soakText, "CONTACT_EPISODE_SAMPLE"), 0,
  "light soak should write no periodic contact samples")
assertEquals(soakSnapshot.records, 20,
  "light soak should contain only physical starts and ends")
assertEquals(soakSnapshot.fileCount, 1,
  "light 10,000-tick soak should not roll over")
assertEquals(soakSnapshot.agentAuditWriteCalls, 2,
  "start batch and end batch should require two storage writes")

-- Dense contact uses events already produced by simulation; logger does no scan.
local denseWrites = {}
local dense = AgentAudit.new({
  writer = function(key, bytes) denseWrites[key] = bytes end,
  forensicEnabled = false
})
local densePopulation = {}
for index = 1, 6 do
  densePopulation[index] = pokemon("wild:dense:" .. index, 20 + index)
end
Relationships.setMutationSink(function(mutation) dense:observeMutation(mutation) end)
Social.setContactSink(function(contact) dense:observeContact(contact) end)
for tick = 1, 200 do
  for leftIndex = 1, #densePopulation - 1 do
    for rightIndex = leftIndex + 1, #densePopulation do
      local left = densePopulation[leftIndex]
      local right = densePopulation[rightIndex]
      Social.observeNearby(left, right.id, 2, tick, right)
      Social.observeNearby(right, left.id, 2, tick, left)
    end
  end
  dense:sample(tick, {})
end
dense:sample(231, {})
dense:flush(231, true)
local denseSnapshot = dense:snapshot()
assertEquals(denseSnapshot.contactEpisodesStarted, 15,
  "six dense agents should produce 15 unordered physical pairs")
assertEquals(denseSnapshot.contactEpisodesEnded, 15,
  "dense physical pairs should each end once")
local directedRelationships = 0
for _, entity in ipairs(densePopulation) do
  for _ in pairs(entity.relationships or {}) do
    directedRelationships = directedRelationships + 1
  end
end
assertEquals(directedRelationships, 30,
  "dense physical pairs should retain 30 directed relationships")
assertEquals(denseSnapshot.records, 30,
  "dense light output should remain two records per physical pair")

-- Known asymmetric directions produce one start/end with separate summaries.
local asymmetricWrites = {}
local asymmetric = AgentAudit.new({
  writer = function(key, bytes) asymmetricWrites[key] = bytes end,
  forensicEnabled = false
})
local asymmetricA = pokemon("asymmetric-a", 40)
local asymmetricB = pokemon("asymmetric-b", 41)
asymmetricA.relationships[asymmetricB.id] = {
  familiarity = 50, trust = 0, affinity = 40, threatMemory = 0,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 0
}
asymmetricB.relationships[asymmetricA.id] = {
  familiarity = 10, trust = 0, affinity = 5, threatMemory = 0,
  directThreatMemory = 0, hostility = 0, lastSeenTick = 0
}
local function manualContact(observer, subject, tick)
  asymmetric:observeContact({
    observerId = observer.id, subjectId = subject.id, tick = tick,
    episodeStartTick = 1, distance = 2,
    relationship = Relationships.snapshot(observer.relationships[subject.id]),
    relationshipRef = observer.relationships[subject.id],
    observer = observer, subject = subject
  })
end
manualContact(asymmetricA, asymmetricB, 1)
manualContact(asymmetricB, asymmetricA, 1)
manualContact(asymmetricA, asymmetricB, 2)
manualContact(asymmetricB, asymmetricA, 2)
asymmetric:sample(33, {})
asymmetric:flush(33, true)
local asymmetricText = asymmetricWrites.agent_audit
assertEquals(countRecords(asymmetricText, "CONTACT_EPISODE_START"), 1,
  "asymmetric directions should share one physical start")
assertEquals(countRecords(asymmetricText, "CONTACT_EPISODE_END"), 1,
  "asymmetric directions should share one physical end")
assertTrue(asymmetricText:find("aToB.end.familiarity=50", 1, true)
    and asymmetricText:find("aToB.end.affinity=40", 1, true),
  "A-to-B end summary should retain its values")
assertTrue(asymmetricText:find("bToA.end.familiarity=10", 1, true)
    and asymmetricText:find("bToA.end.affinity=5", 1, true),
  "B-to-A end summary should retain its independent values")

local function runPerformance(mode)
  local observer = pokemon("wild:perf:" .. mode .. ":a", 50)
  local subject = pokemon("wild:perf:" .. mode .. ":b", 51)
  local relationshipWrites = {}
  local agentWrites = {}
  local relationshipAudit = nil
  local agentAudit = nil
  if mode ~= "off" then
    relationshipAudit = RelationshipAudit.new({
      writer = function(key, bytes) relationshipWrites[key] = bytes end
    })
    agentAudit = AgentAudit.new({
      writer = function(key, bytes) agentWrites[key] = bytes end,
      forensicEnabled = mode == "forensic",
      contextProvider = function() return {} end
    })
    Relationships.setMutationSink(function(mutation)
      local _, emission = relationshipAudit:observe(mutation)
      agentAudit:observeMutation(mutation, emission)
    end)
    Social.setContactSink(function(contact) agentAudit:observeContact(contact) end)
  else
    Relationships.setMutationSink(nil)
    Social.setContactSink(nil)
  end
  local started = os.clock()
  for tick = 1, 2000 do
    Social.observeNearby(observer, subject.id, 2, tick, subject)
    if agentAudit and relationshipAudit then
      agentAudit:sample(tick, {})
      relationshipAudit:flush(tick, false)
      agentAudit:flush(tick, false)
    end
  end
  if agentAudit and relationshipAudit then
    agentAudit:sample(2031, {})
    relationshipAudit:flush(2031, true)
    agentAudit:flush(2031, true)
  end
  return {
    seconds = os.clock() - started,
    relationship = relationshipAudit and relationshipAudit:snapshot() or {},
    agent = agentAudit and agentAudit:snapshot() or {}
  }
end

local off = runPerformance("off")
local light = runPerformance("light")
local forensic = runPerformance("forensic")
assertTrue((light.agent.records or 0) < (forensic.agent.records or 0),
  "light mode should emit fewer records than forensic mode")
assertTrue((light.agent.agentAuditBytesWritten or 0)
    < (forensic.agent.agentAuditBytesWritten or 0),
  "light mode should write fewer bytes than forensic mode")

print(string.format(
  "TELEMETRY_CLEANUP agentSoakTicks=10000 physicalEpisodes=%d records=%d bytes=%d writes=%d files=%d recordsPer1000=%.2f bytesPer1000=%.2f densePhysicalPairs=%d denseDirectedRelationships=%d denseRecords=%d soakSeconds=%.6f offSeconds=%.6f lightSeconds=%.6f forensicSeconds=%.6f lightAgentRecords=%d lightAgentBytes=%d forensicAgentRecords=%d forensicAgentBytes=%d",
  soakSnapshot.contactEpisodesStarted, soakSnapshot.records,
  soakSnapshot.agentAuditBytesWritten, soakSnapshot.agentAuditWriteCalls,
  soakSnapshot.fileCount, soakSnapshot.records / 10,
  soakSnapshot.agentAuditBytesWritten / 10,
  denseSnapshot.contactEpisodesStarted, directedRelationships,
  denseSnapshot.records, soakSeconds, off.seconds, light.seconds,
  forensic.seconds, light.agent.records or 0,
  light.agent.agentAuditBytesWritten or 0,
  forensic.agent.records or 0,
  forensic.agent.agentAuditBytesWritten or 0
))

Relationships.setMutationSink(nil)
Social.setContactSink(nil)

return true
