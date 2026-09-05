local AgentAudit = require("src.debug.agent_audit")
local RelationshipAudit = require("src.debug.relationship_audit")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function mutation(tick, created)
  return {
    observerId = "epoch-a",
    subjectId = "epoch-b",
    event = created and "SOCIAL_NEARBY" or "TEST_MUTATION",
    tick = tick,
    created = created == true,
    before = { familiarity = created and 0 or 9 },
    relationship = { familiarity = created and 1 or 10 },
    relationshipRef = {}
  }
end

local relationshipWrites = {}
local relationshipAudit = RelationshipAudit.new({
  epochStartTick = 5001,
  writer = function(key, bytes) relationshipWrites[key] = bytes end
})
relationshipAudit:observe(mutation(1, true))
relationshipAudit:observe(mutation(5001, true))
relationshipAudit:observe(mutation(5005, false))
assertTrue(relationshipAudit:flush(5010, true),
  "relationship audit epoch should flush")
local relationshipText = relationshipWrites.relationship_audit or ""
assertEquals(relationshipText:find("tick=1\t", 1, true), nil,
  "relationship audit must not replay pre-epoch mutations")
assertTrue(relationshipText:find("type=AUDIT_EPOCH_START", 1, true) ~= nil,
  "relationship audit should identify its file-output epoch")
assertTrue(relationshipText:find("tick=5001", 1, true) ~= nil,
  "relationship audit should create its file at enable")

local agentWrites = {}
local agentAudit = AgentAudit.new({
  epochStartTick = 5001,
  writer = function(key, bytes) agentWrites[key] = bytes end
})
agentAudit:observeMutation(mutation(20, true))
agentAudit:observeContact({
  observerId = "epoch-a",
  subjectId = "epoch-b",
  tick = 5002,
  episodeStartTick = 100,
  distance = 2,
  relationship = { familiarity = 50 },
  observer = { id = "epoch-a", relationships = {} },
  subject = { id = "epoch-b", relationships = {} }
})
assertTrue(agentAudit:flush(5010, true), "agent audit epoch should flush")
local agentText = agentWrites.agent_audit or ""
assertEquals(agentText:find("tick=20\t", 1, true), nil,
  "agent audit must not replay pre-epoch mutations")
assertTrue(agentText:find("type=CONTACT_EPISODE_ALREADY_ACTIVE", 1, true)
    ~= nil,
  "a contact predating enable should emit one compact active snapshot")
assertTrue(agentText:find("contactEpisodeStartTick=100", 1, true) ~= nil,
  "active-contact snapshot should retain the mechanics episode start")
assertTrue(agentText:find("auditEpochStartTick=5001", 1, true) ~= nil,
  "active-contact snapshot should identify the output epoch")

local secondWrites = {}
local secondEpoch = RelationshipAudit.new({
  epochStartTick = 10001,
  writer = function(key, bytes) secondWrites[key] = bytes end
})
secondEpoch:observe(mutation(9000, true))
secondEpoch:observe(mutation(10002, true))
secondEpoch:flush(10010, true)
local secondText = secondWrites.relationship_audit or ""
assertEquals(secondText:find("tick=9000", 1, true), nil,
  "reenable must exclude events from the disabled interval")
assertTrue(secondText:find("tick=10002", 1, true) ~= nil,
  "reenable should record new mutations")

return true