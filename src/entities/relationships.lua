local Relationships = {}
local Config = require("src.core.config")
local Utility = require("src.behavior.utility")
local mutationSink = nil
local diagnosticSink = nil
local pendingCreation = setmetatable({}, { __mode = "k" })
local MUTATION_FIELDS = {
  "familiarity", "trust", "affinity", "threatMemory",
  "directThreatMemory", "hostility", "lastSeenTick", "importance"
}

local function clamp(value, minV, maxV)
  if value < minV then
    return minV
  end
  if value > maxV then
    return maxV
  end
  return value
end

function Relationships.setMutationSink(sink)
  mutationSink = type(sink) == "function" and sink or nil
end

function Relationships.setDiagnosticSink(sink)
  diagnosticSink = type(sink) == "function" and sink or nil
end

function Relationships.emitDiagnosticEvent(event)
  if diagnosticSink then diagnosticSink(event) end
end

function Relationships.snapshot(relationship)
  local snapshot = {}
  for _, field in ipairs(MUTATION_FIELDS) do
    snapshot[field] = relationship and relationship[field] or nil
  end
  return snapshot
end

function Relationships.recordMutation(entity, targetEntityId, eventName, before,
  relationship, nowTick, producer, diagnosticContext)
  local changes = {}
  for _, field in ipairs(MUTATION_FIELDS) do
    local oldValue = before and before[field] or nil
    local newValue = relationship and relationship[field] or nil
    if oldValue ~= newValue then
      changes[#changes + 1] = { field = field, old = oldValue, new = newValue }
    end
  end
  if #changes == 0 then return nil end
  local mutation = {
    observerId = entity and entity.id or nil,
    subjectId = targetEntityId,
    event = eventName,
    tick = nowTick,
    changes = changes,
    before = Relationships.snapshot(before),
    relationship = Relationships.snapshot(relationship),
    relationshipRef = relationship,
    producer = producer or "src.entities.relationships",
    diagnosticContext = diagnosticContext,
    created = pendingCreation[relationship] == true
  }
  pendingCreation[relationship] = nil
  if mutationSink then mutationSink(mutation) end
  return mutation
end

function Relationships.applyPerceptionEvent(entity, targetEntityId, eventName, payload, nowTick)
  if eventName == "ENTITY_NEAR" then
    return entity.relationships and entity.relationships[targetEntityId] or nil
  end
  local relationship = Relationships.getOrCreate(entity, targetEntityId)
  local before = Relationships.snapshot(relationship)
  local eventData = payload or {}
  local tick = nowTick or relationship.lastSeenTick or 0
  local threatDelta = eventData.threatDelta or 0

  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.perceivedFear = entity.runtimeState.perceivedFear or {}
  local perceivedFear = entity.runtimeState.perceivedFear
  perceivedFear[targetEntityId] = perceivedFear[targetEntityId] or 0

  if eventName == "ENTITY_SEEN" then
    relationship.familiarity = clamp((relationship.familiarity or 0) + (eventData.familiarityDelta or 1), 0, 100)
    relationship.lastSeenTick = tick
  elseif eventName == "ENTITY_APPROACHING" then
    perceivedFear[targetEntityId] = clamp(perceivedFear[targetEntityId] + threatDelta, 0, 100)
    relationship.lastSeenTick = tick
  elseif eventName == "ENTITY_RETREATING" then
    perceivedFear[targetEntityId] = clamp(perceivedFear[targetEntityId] - (eventData.fearRelief or 1), 0, 100)
    relationship.lastSeenTick = tick
  elseif eventName == "ENTITY_ATTACKED" then
    relationship.threatMemory = clamp((relationship.threatMemory or 0) + (threatDelta > 0 and threatDelta or 2), 0, 100)
    relationship.directThreatMemory = clamp((relationship.directThreatMemory or 0) + (threatDelta > 0 and threatDelta or 2), 0, 100)
    entity.runtimeState.directThreatEvidence = entity.runtimeState.directThreatEvidence or {}
    entity.runtimeState.directThreatEvidence[targetEntityId] = {
      severity = math.max(threatDelta, 1),
      tick = tick,
      reason = "ENTITY_ATTACKED"
    }
    relationship.lastSeenTick = tick
  elseif eventName == "ENTITY_FLED" then
    relationship.threatMemory = clamp((relationship.threatMemory or 0) + (threatDelta > 0 and threatDelta or 2), 0, 100)
    relationship.lastSeenTick = tick
  elseif eventName == "ENTITY_LOST" then
    perceivedFear[targetEntityId] = clamp(perceivedFear[targetEntityId] - (eventData.fearRelief or 1), 0, 100)
  end

  Relationships.recordMutation(entity, targetEntityId, eventName, before,
    relationship, tick, "src.entities.relationships.applyPerceptionEvent")
  return relationship
end

function Relationships.getOrCreate(entity, targetEntityId)
  entity.relationships = entity.relationships or {}

  if not entity.relationships[targetEntityId] then
    entity.relationships[targetEntityId] = {
      familiarity = 0,
      trust = 0,
      affinity = 0,
      threatMemory = 0,
      directThreatMemory = 0,
      hostility = 0,
      lastSeenTick = 0,
      lastCalmTick = -999999,
      lastVisitSerial = 0,
      calmWarmupThisVisit = 0,
      importance = 0.1
    }
    pendingCreation[entity.relationships[targetEntityId]] = true
  end

  return entity.relationships[targetEntityId]
end

function Relationships.observeCalmProximity(entity, targetEntityId, nowTick, cooldownTicks, distance)
  entity.relationships = entity.relationships or {}
  local rel = entity.relationships[targetEntityId]
  local _band, multiplier = Utility.distanceBand(distance)
  if not rel and multiplier <= 0 then
    return nil, false
  end
  rel = rel or Relationships.getOrCreate(entity, targetEntityId)
  local before = Relationships.snapshot(rel)
  local visitSerial = entity and entity.memory and entity.memory.debug and entity.memory.debug.respawnCount or 0

  if rel.lastVisitSerial ~= visitSerial then
    rel.lastVisitSerial = visitSerial
    rel.calmWarmupThisVisit = 0
  end

  local currentTick = nowTick or (rel.lastSeenTick + 1)
  local cooldown = cooldownTicks or 0
  local canApplyGain = (currentTick - rel.lastCalmTick) >= cooldown

  rel.lastSeenTick = currentTick
  if not canApplyGain then
    Relationships.recordMutation(entity, targetEntityId, "CALM_PROXIMITY",
      before, rel, currentTick,
      "src.entities.relationships.observeCalmProximity")
    return rel, false
  end

  local warmupCap = (entity and entity.relationshipWarmupCap) or ((Config.phase0 and Config.phase0.warmupPerVisitCap) or 0)
  local trustGain = 1 * multiplier
  local threatLoss = 0.1 * multiplier
  if multiplier <= 0 then
    Relationships.recordMutation(entity, targetEntityId, "CALM_PROXIMITY",
      before, rel, currentTick,
      "src.entities.relationships.observeCalmProximity")
    return rel, false
  end

  rel.familiarity = clamp(rel.familiarity + trustGain, 0, 100)
  rel.threatMemory = clamp(rel.threatMemory - threatLoss, 0, 100)

  local appliedTrustGain = false
  if warmupCap <= 0 or rel.calmWarmupThisVisit < warmupCap then
    rel.trust = clamp(rel.trust + trustGain, 0, 100)
    rel.calmWarmupThisVisit = rel.calmWarmupThisVisit + 1
    appliedTrustGain = true
    rel.lastCalmTick = currentTick
  end

  rel.lastCalmTick = currentTick
  Relationships.recordMutation(entity, targetEntityId, "CALM_PROXIMITY",
    before, rel, currentTick,
    "src.entities.relationships.observeCalmProximity")
  return rel, appliedTrustGain
end

function Relationships.applySocialFear(entity, sourceEntityId, targetEntityId, nowTick, fearSignal, cooldownTicks, distance)
  local sourceRel = Relationships.getOrCreate(entity, sourceEntityId)
  local targetRel = Relationships.getOrCreate(entity, targetEntityId)
  local before = Relationships.snapshot(targetRel)

  local currentTick = nowTick or targetRel.lastSeenTick or 0
  local cooldown = cooldownTicks or 0
  local lastTick = targetRel.lastSocialFearTick or -999999
  if (currentTick - lastTick) < cooldown then
    targetRel.lastSeenTick = currentTick
    Relationships.recordMutation(entity, targetEntityId, "SOCIAL_FEAR",
      before, targetRel, currentTick,
      "src.entities.relationships.applySocialFear")
    return targetRel, 0, false
  end

  local trustWeight = clamp((sourceRel.trust or 0) / 100, 0, 1)
  local signal = fearSignal or 0
  local _, distanceMultiplier = Utility.distanceBand(distance)
  local threatDelta = signal * trustWeight * distanceMultiplier

  targetRel.lastSeenTick = currentTick
  targetRel.lastSocialFearTick = currentTick
  if threatDelta <= 0 then
    Relationships.recordMutation(entity, targetEntityId, "SOCIAL_FEAR",
      before, targetRel, currentTick,
      "src.entities.relationships.applySocialFear")
    return targetRel, 0, false
  end
  targetRel.threatMemory = clamp((targetRel.threatMemory or 0) + threatDelta, 0, 100)
  targetRel.trust = clamp((targetRel.trust or 0) - (threatDelta * 0.25), 0, 100)

  Relationships.recordMutation(entity, targetEntityId, "SOCIAL_FEAR",
    before, targetRel, currentTick,
    "src.entities.relationships.applySocialFear")
  return targetRel, threatDelta, true
end

function Relationships.applySocialReassurance(entity, sourceEntityId, targetEntityId, nowTick, reassuranceSignal, cooldownTicks, distance)
  local sourceRel = Relationships.getOrCreate(entity, sourceEntityId)
  local targetRel = Relationships.getOrCreate(entity, targetEntityId)
  local before = Relationships.snapshot(targetRel)

  local currentTick = nowTick or targetRel.lastSeenTick or 0
  local cooldown = cooldownTicks or 0
  local lastTick = targetRel.lastSocialReassuranceTick or -999999
  if (currentTick - lastTick) < cooldown then
    targetRel.lastSeenTick = currentTick
    Relationships.recordMutation(entity, targetEntityId,
      "SOCIAL_REASSURANCE", before, targetRel, currentTick,
      "src.entities.relationships.applySocialReassurance")
    return targetRel, 0, false
  end

  local trustWeight = clamp((sourceRel.trust or 0) / 100, 0, 1)
  local signal = reassuranceSignal or 0
  local _, distanceMultiplier = Utility.distanceBand(distance)
  local calmDelta = signal * trustWeight * distanceMultiplier

  targetRel.lastSeenTick = currentTick
  targetRel.lastSocialReassuranceTick = currentTick
  if calmDelta <= 0 then
    Relationships.recordMutation(entity, targetEntityId,
      "SOCIAL_REASSURANCE", before, targetRel, currentTick,
      "src.entities.relationships.applySocialReassurance")
    return targetRel, 0, false
  end

  targetRel.threatMemory = clamp((targetRel.threatMemory or 0) - calmDelta, 0, 100)
  targetRel.trust = clamp((targetRel.trust or 0) + (calmDelta * 0.25), 0, 100)

  Relationships.recordMutation(entity, targetEntityId,
    "SOCIAL_REASSURANCE", before, targetRel, currentTick,
    "src.entities.relationships.applySocialReassurance")
  return targetRel, calmDelta, true
end

return Relationships
