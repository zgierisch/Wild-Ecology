local AgentAudit = {}
AgentAudit.__index = AgentAudit

local DEFAULT_MAX_BYTES = 196 * 1024
local DEFAULT_FLUSH_INTERVAL_TICKS = 30
local DEFAULT_SEPARATION_TICKS = 30
local DEFAULT_CONTACT_SAMPLE_TICKS = 100
local DEFAULT_HISTORY_SAMPLES = 45
local DEFAULT_POST_SAMPLES = 25
local DEFAULT_PERIODIC_TICKS = 300
local LARGE_DELTA_THRESHOLD = 25
local STORAGE_KEY = "agent_audit"

local RELATIONSHIP_FIELDS = {
  "familiarity", "trust", "affinity", "threatMemory",
  "directThreatMemory", "hostility", "lastSeenTick"
}

local function sanitize(value)
  if value == nil then return "none" end
  return tostring(value):gsub("[\t\r\n]", " ")
end

local function number(value)
  if type(value) ~= "number" then return sanitize(value) end
  if value == math.floor(value) then return tostring(value) end
  return string.format("%.4f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function pairKey(observerId, subjectId)
  return tostring(observerId) .. "\31" .. tostring(subjectId)
end

local function physicalPair(observerId, subjectId)
  local left = tostring(observerId)
  local right = tostring(subjectId)
  if right < left then left, right = right, left end
  return left .. "\31" .. right, left, right
end

local function relationshipFrom(entity, targetId)
  return entity and entity.relationships and entity.relationships[targetId]
end

local function copyRelationship(snapshot)
  local result = {}
  for _, field in ipairs(RELATIONSHIP_FIELDS) do
    result[field] = snapshot and snapshot[field] or 0
  end
  return result
end

local function segmentKey(baseKey, index)
  if index == 1 then return baseKey end
  return baseKey .. "_" .. tostring(index)
end

local function newSegment()
  return { records = {}, bytes = 0, dirty = false }
end

local function add(parts, key, value)
  parts[#parts + 1] = key .. "=" .. sanitize(value)
end

local function addRelationship(parts, prefix, values)
  for _, field in ipairs(RELATIONSHIP_FIELDS) do
    add(parts, prefix .. field, number(values and values[field] or 0))
  end
end

local function addActor(parts, prefix, actor)
  actor = actor or {}
  local fields = {
    "id", "persistentId", "species", "kind", "map", "cellX", "cellY",
    "behavior", "previousBehavior", "targetEntityId", "targetDestination",
    "intentState", "intentTargetId", "intentProgress", "intentCommitment",
    "intentSatisfaction", "intentRejections", "intentFailures",
    "spatialGoalKind", "spatialGoalTarget", "movementRequest", "motionActive",
    "motionSource", "motionDestination", "navigationGoal", "navigationReference",
    "navigationReplanReason", "fearCurrent", "fearDirect", "fearSocial",
    "primaryThreatId", "directThreatId", "escapeReferenceKind", "socialOnly",
    "groupId", "sociality", "independence", "relationshipCount", "nearbyCount"
  }
  for _, field in ipairs(fields) do add(parts, prefix .. field, actor[field]) end
end

function AgentAudit.new(options)
  local settings = options or {}
  local audit = setmetatable({
    maxBytes = settings.maxBytes or DEFAULT_MAX_BYTES,
    flushIntervalTicks = settings.flushIntervalTicks or DEFAULT_FLUSH_INTERVAL_TICKS,
    separationTicks = settings.separationTicks or DEFAULT_SEPARATION_TICKS,
    contactSampleTicks = settings.contactSampleTicks
      or DEFAULT_CONTACT_SAMPLE_TICKS,
    historyLimit = settings.historySamples or DEFAULT_HISTORY_SAMPLES,
    postSamples = settings.postSamples or DEFAULT_POST_SAMPLES,
    periodicTicks = settings.periodicTicks or DEFAULT_PERIODIC_TICKS,
    storageKey = settings.storageKey or STORAGE_KEY,
    writer = settings.writer,
    contextProvider = settings.contextProvider,
    forensicEnabled = settings.forensicEnabled,
    epochStartTick = settings.epochStartTick,
    segments = { newSegment() },
    segmentIndex = 1,
    nextSequence = 1,
    objectTokens = setmetatable({}, { __mode = "k" }),
    nextObjectToken = 1,
    pairObjectTokens = {},
    pairObjectSnapshots = {},
    episodes = {},
    episodeSerials = {},
    previousEpisodeEnds = {},
    histories = {},
    postWindows = {},
    importantByPair = {},
    lastPeriodicTick = nil,
    lastFlushTick = nil,
    writeFailureReported = false,
    counters = {
      records = 0,
      mutations = 0,
      rotations = 0,
      dropped = 0,
      writeFailures = 0,
      objectReplacements = 0,
      largeDeltas = 0,
      decreases = 0,
      contactEpisodesStarted = 0,
      contactEpisodesEnded = 0,
      auditMismatches = 0
      , noOpMutations = 0
      , contactObservations = 0
      , bytes = 0
      , agentAuditWriteCalls = 0
      , agentAuditBytesWritten = 0
      , recordTypes = {}
    }
  }, AgentAudit)
  if audit.epochStartTick ~= nil then
    audit:_append("AUDIT_EPOCH_START", audit.epochStartTick, {
      "auditEpochStartTick=" .. sanitize(audit.epochStartTick)
    })
  end
  return audit
end

function AgentAudit:_append(recordType, tick, fields)
  if self.epochStartTick ~= nil and type(tick) == "number"
    and tick < self.epochStartTick then
    return false
  end
  local sequence = self.nextSequence
  self.nextSequence = sequence + 1
  local parts = { "v=1", "seq=" .. sequence, "tick=" .. sanitize(tick),
    "type=" .. recordType }
  for _, item in ipairs(fields or {}) do parts[#parts + 1] = item end
  local framed = table.concat(parts, "\t") .. "\n"
  if #framed > self.maxBytes then
    self.counters.dropped = self.counters.dropped + 1
    return false
  end
  local segment = self.segments[self.segmentIndex]
  if segment.bytes + #framed > self.maxBytes then
    local previousKey = segmentKey(self.storageKey, self.segmentIndex)
    self.segmentIndex = self.segmentIndex + 1
    segment = newSegment()
    self.segments[self.segmentIndex] = segment
    self.counters.rotations = self.counters.rotations + 1
    local continuation = {
      "v=1", "seq=" .. sequence, "tick=" .. sanitize(tick),
      "type=AUDIT_FILE_CONTINUATION",
      "previous=" .. previousKey,
      "current=" .. segmentKey(self.storageKey, self.segmentIndex)
    }
    local recordSequence = self.nextSequence
    self.nextSequence = recordSequence + 1
    framed = framed:gsub("^v=1\tseq=" .. tostring(sequence) .. "\t",
      "v=1\tseq=" .. tostring(recordSequence) .. "\t", 1)
    framed = table.concat(continuation, "\t") .. "\n" .. framed
  end
  segment.records[#segment.records + 1] = framed
  segment.bytes = segment.bytes + #framed
  segment.dirty = true
  self.counters.records = self.counters.records + 1
  self.counters.bytes = self.counters.bytes + #framed
  self.counters.recordTypes[recordType]
    = (self.counters.recordTypes[recordType] or 0) + 1
  return true
end

function AgentAudit:_forensicEnabled()
  if type(self.forensicEnabled) == "function" then
    local ok, enabled = pcall(self.forensicEnabled)
    return ok and enabled == true
  end
  return self.forensicEnabled == true
end

function AgentAudit:_objectToken(relationship)
  if type(relationship) ~= "table" then return "none" end
  local token = self.objectTokens[relationship]
  if not token then
    token = "rel-" .. tostring(self.nextObjectToken)
    self.nextObjectToken = self.nextObjectToken + 1
    self.objectTokens[relationship] = token
  end
  return token
end

function AgentAudit:_context(mutation)
  if type(self.contextProvider) ~= "function" then return {} end
  local ok, context = pcall(self.contextProvider, mutation)
  return ok and type(context) == "table" and context or {}
end

function AgentAudit:_flushHistory(actorId, tick, reason)
  local history = self.histories[actorId] or {}
  for _, sample in ipairs(history) do
    local fields = {}
    add(fields, "actor", actorId)
    add(fields, "triggerTick", tick)
    add(fields, "reason", reason)
    addActor(fields, "sample.", sample)
    self:_append("AGENT_HISTORY_PRE", sample.tick, fields)
  end
  self.postWindows[actorId] = math.max(self.postWindows[actorId] or 0,
    self.postSamples)
end

function AgentAudit:_important(mutation, context, reason)
  self:_flushHistory(mutation.observerId, mutation.tick, reason)
  if context.subject and context.subject.kind == "POKEMON" then
    self:_flushHistory(mutation.subjectId, mutation.tick, reason)
  end
end

function AgentAudit:_mutationFields(mutation, context, before, after, token, episode)
  local fields = {}
  add(fields, "observer", mutation.observerId)
  add(fields, "subject", mutation.subjectId)
  add(fields, "event", mutation.event)
  add(fields, "producer", mutation.producer)
  add(fields, "relationshipObject", token)
  add(fields, "created", mutation.created == true)
  add(fields, "canonicalConstructorCalled", mutation.created == true)
  add(fields, "distance", context.distance)
  add(fields, "sameGroup", context.sameGroup)
  add(fields, "sameSpecies", context.sameSpecies)
  add(fields, "socialCompatibility", context.socialCompatibility)
  addActor(fields, "observer.", context.observer)
  addActor(fields, "subject.", context.subject)
  addRelationship(fields, "before.", before)
  addRelationship(fields, "after.", after)
  if episode then
    add(fields, "contactEpisode", episode.id)
    add(fields, "contactEpisodeStartTick", episode.startTick)
    add(fields, "continuousProximityTicks", (mutation.tick or 0) - episode.startTick)
    add(fields, "lastContactTick", episode.lastContactTick)
    add(fields, "previousContactEpisodeEndTick", episode.previousEndTick)
    add(fields, "previousContactTick", episode.previousLastContactTick)
    add(fields, "timeSincePreviousContactEpisode", episode.previousEndTick and
      (episode.startTick - episode.previousEndTick) or nil)
    add(fields, "timeSincePreviousContact", episode.previousLastContactTick and
      (episode.startTick - episode.previousLastContactTick) or nil)
    add(fields, "socialNearbyIndex", episode.socialNearbyCount)
    add(fields, "relationshipMutationIndex", episode.mutationCount)
    add(fields, "sincePreviousSocialNearby", episode.priorSocialTick and
      ((mutation.tick or 0) - episode.priorSocialTick) or nil)
    episode.priorSocialTick = mutation.event == "SOCIAL_NEARBY"
      and mutation.tick or episode.priorSocialTick
  end
  local important = self.importantByPair[pairKey(mutation.observerId,
    mutation.subjectId)]
  if important and important.tick ~= mutation.tick then
    add(fields, "previousImportantEvent", important.event)
    add(fields, "ticksSinceImportantEvent", (mutation.tick or 0) - important.tick)
    self.importantByPair[pairKey(mutation.observerId, mutation.subjectId)] = nil
  end
  return fields
end

function AgentAudit:_compactRelationshipFields(mutation, before, after, episode)
  local fields = {}
  add(fields, "observer", mutation.observerId)
  add(fields, "subject", mutation.subjectId)
  add(fields, "event", mutation.event)
  add(fields, "producer", mutation.producer)
  if episode then
    add(fields, "episode", episode.id)
    add(fields, "episodeAge", (mutation.tick or 0) - episode.startTick)
  end
  addRelationship(fields, "before.", before)
  addRelationship(fields, "after.", after)
  return fields
end

function AgentAudit:observeContact(contact)
  if type(contact) ~= "table" or contact.observerId == nil
    or contact.subjectId == nil then return false end
  self.counters.contactObservations = self.counters.contactObservations + 1
  local key, entityA, entityB = physicalPair(contact.observerId,
    contact.subjectId)
  local episode = self.episodes[key]
  if not episode
    or (contact.tick or 0) - episode.lastContactTick > self.separationTicks then
    local serial = (self.episodeSerials[key] or 0) + 1
    self.episodeSerials[key] = serial
    local previousEnd = self.previousEpisodeEnds[key]
    local entityById = {
      [tostring(contact.observerId)] = contact.observer,
      [tostring(contact.subjectId)] = contact.subject
    }
    local relationshipAToB = relationshipFrom(entityById[entityA], entityB)
    local relationshipBToA = relationshipFrom(entityById[entityB], entityA)
    episode = {
      id = serial,
      contactObserved = true,
      startTick = contact.episodeStartTick or contact.tick or 0,
      lastContactTick = contact.tick or 0,
      entityA = entityA,
      entityB = entityB,
      map = contact.observer and contact.observer.home
        and contact.observer.home.mapId,
      socialNearbyObservationCount = 0,
      entityNearObservationCount = 0,
      lastObservationTick = nil,
      directions = {
        [pairKey(entityA, entityB)] = {
          observer = entityA, subject = entityB,
          existedAtStart = relationshipAToB ~= nil,
          createdDuringEpisode = false,
          socialExposureMutationCount = 0,
          relationshipMutationCount = 0,
          startValues = copyRelationship(relationshipAToB),
          latestValues = copyRelationship(relationshipAToB)
        },
        [pairKey(entityB, entityA)] = {
          observer = entityB, subject = entityA,
          existedAtStart = relationshipBToA ~= nil,
          createdDuringEpisode = false,
          socialExposureMutationCount = 0,
          relationshipMutationCount = 0,
          startValues = copyRelationship(relationshipBToA),
          latestValues = copyRelationship(relationshipBToA)
        }
      },
      minDistance = contact.distance,
      maxDistance = contact.distance,
      behaviors = {},
      nextSampleTick = (contact.tick or 0) + self.contactSampleTicks,
      previousEndTick = previousEnd and previousEnd.endTick,
      previousLastContactTick = previousEnd and previousEnd.lastContactTick
    }
    self.episodes[key] = episode
    self.counters.contactEpisodesStarted
      = self.counters.contactEpisodesStarted + 1
    local fields = {}
    add(fields, "episode", episode.id)
    add(fields, "entityA", entityA)
    add(fields, "entityB", entityB)
    add(fields, "map", episode.map)
    add(fields, "distance", contact.distance)
    add(fields, "previousContactEpisodeEndTick", episode.previousEndTick)
    add(fields, "previousContactTick", episode.previousLastContactTick)
    add(fields, "timeSincePreviousContactEpisode", episode.previousEndTick and
      ((contact.tick or 0) - episode.previousEndTick) or nil)
    add(fields, "timeSincePreviousContact", episode.previousLastContactTick and
      ((contact.tick or 0) - episode.previousLastContactTick) or nil)
    add(fields, "aToB.existed", relationshipAToB ~= nil)
    addRelationship(fields, "aToB.", relationshipAToB)
    add(fields, "bToA.existed", relationshipBToA ~= nil)
    addRelationship(fields, "bToA.", relationshipBToA)
    local predatesEpoch = self.epochStartTick ~= nil
      and (contact.episodeStartTick or contact.tick or 0) < self.epochStartTick
    if predatesEpoch then
      add(fields, "contactEpisodeStartTick", episode.startTick)
      add(fields, "auditEpochStartTick", self.epochStartTick)
    end
    self:_append(predatesEpoch and "CONTACT_EPISODE_ALREADY_ACTIVE"
      or "CONTACT_EPISODE_START", contact.tick, fields)
  end

  episode.lastContactTick = contact.tick or episode.lastContactTick
  if episode.lastObservationTick ~= contact.tick then
    episode.socialNearbyObservationCount
      = episode.socialNearbyObservationCount + 1
    if type(contact.distance) == "number" and contact.distance <= 2 then
      episode.entityNearObservationCount
        = episode.entityNearObservationCount + 1
    end
    episode.lastObservationTick = contact.tick
  end
  if type(contact.distance) == "number" then
    episode.minDistance = math.min(episode.minDistance or contact.distance,
      contact.distance)
    episode.maxDistance = math.max(episode.maxDistance or contact.distance,
      contact.distance)
  end
  local direction = episode.directions[pairKey(contact.observerId,
    contact.subjectId)]
  if direction then
    direction.latestValues = copyRelationship(contact.relationship)
  end
  local observerBehavior = contact.observer and contact.observer.runtimeState
    and contact.observer.runtimeState.state
  local subjectBehavior = contact.subject and contact.subject.runtimeState
    and contact.subject.runtimeState.state
  if observerBehavior then episode.behaviors[observerBehavior] = true end
  if subjectBehavior then
    episode.behaviors["subject:" .. subjectBehavior] = true
  end

  if self:_forensicEnabled()
    and (contact.tick or 0) >= episode.nextSampleTick then
    local fields = {}
    add(fields, "entityA", episode.entityA)
    add(fields, "entityB", episode.entityB)
    add(fields, "episode", episode.id)
    add(fields, "episodeAge", (contact.tick or 0) - episode.startTick)
    add(fields, "distance", contact.distance)
    add(fields, "observerBehavior", observerBehavior)
    add(fields, "subjectBehavior", subjectBehavior)
    add(fields, "socialNearbyObservationCount",
      episode.socialNearbyObservationCount)
    add(fields, "entityNearObservationCount",
      episode.entityNearObservationCount)
    add(fields, "directedRelationshipMutationCount",
      (episode.directions[pairKey(episode.entityA, episode.entityB)]
        .relationshipMutationCount or 0)
      + (episode.directions[pairKey(episode.entityB, episode.entityA)]
        .relationshipMutationCount or 0))
    self:_append("CONTACT_EPISODE_SAMPLE", contact.tick, fields)
    episode.nextSampleTick = (contact.tick or 0) + self.contactSampleTicks
  end
  return true
end

function AgentAudit:observeMutation(mutation, relationshipAuditEmission)
  if type(mutation) ~= "table" or mutation.observerId == nil
    or mutation.subjectId == nil then return false end
  self.counters.mutations = self.counters.mutations + 1
  local before = copyRelationship(mutation.before)
  local after = copyRelationship(mutation.relationship)
  local token = self:_objectToken(mutation.relationshipRef)
  local key = pairKey(mutation.observerId, mutation.subjectId)
  local physicalKey = physicalPair(mutation.observerId, mutation.subjectId)
  local episode = self.episodes[physicalKey]
  local direction = episode and episode.directions
    and episode.directions[key]
  if direction then
    direction.relationshipMutationCount
      = direction.relationshipMutationCount + 1
    if mutation.event == "SOCIAL_NEARBY" then
      direction.socialExposureMutationCount
        = direction.socialExposureMutationCount + 1
    end
    direction.createdDuringEpisode = direction.createdDuringEpisode
      or mutation.created == true
    direction.latestValues = copyRelationship(after)
  end

  local meaningfulChange = false
  for _, field in ipairs({ "familiarity", "trust", "affinity",
    "threatMemory", "directThreatMemory", "hostility" }) do
    if (before[field] or 0) ~= (after[field] or 0) then
      meaningfulChange = true
      break
    end
  end
  if not meaningfulChange then
    self.counters.noOpMutations = self.counters.noOpMutations + 1
  end

  local context = nil
  local function richFields()
    context = context or self:_context(mutation)
    return self:_mutationFields(mutation, context, before, after, token,
      episode)
  end
  local priorToken = self.pairObjectTokens[key]
  if priorToken and priorToken ~= token then
    local fields = richFields()
    add(fields, "oldRelationshipObject", priorToken)
    addRelationship(fields, "oldObject.", self.pairObjectSnapshots[key])
    self:_append("RELATIONSHIP_OBJECT_REPLACED", mutation.tick, fields)
    self.counters.objectReplacements = self.counters.objectReplacements + 1
    context = context or self:_context(mutation)
    self:_important(mutation, context, "RELATIONSHIP_OBJECT_REPLACED")
  end
  self.pairObjectTokens[key] = token
  self.pairObjectSnapshots[key] = copyRelationship(after)

  if type(mutation.relationshipRef) ~= "table" then
    self:_append("RELATIONSHIP_PROVENANCE_ANOMALY", mutation.tick,
      richFields())
    context = context or self:_context(mutation)
    self:_important(mutation, context, "RELATIONSHIP_PROVENANCE_ANOMALY")
  end

  if self:_forensicEnabled() and meaningfulChange then
    self:_append("RELATIONSHIP_MUTATION", mutation.tick, richFields())
  end

  for _, field in ipairs(RELATIONSHIP_FIELDS) do
    if field ~= "lastSeenTick" then
      local oldValue = before[field] or 0
      local newValue = after[field] or 0
      local delta = newValue - oldValue
      local peacefulField = field == "familiarity" or field == "trust"
        or field == "affinity"
      local largeDecrease = peacefulField and delta < -LARGE_DELTA_THRESHOLD
      local unexpectedDecrease = peacefulField and delta < 0
        and not (field == "trust" and mutation.event == "SOCIAL_FEAR")
      if largeDecrease or unexpectedDecrease then
        local anomaly = richFields()
        add(anomaly, "field", field)
        add(anomaly, "delta", number(delta))
        local recordType = largeDecrease and "RELATIONSHIP_LARGE_DECREASE"
          or "RELATIONSHIP_DECREASE"
        self:_append(recordType, mutation.tick, anomaly)
        self.counters.decreases = self.counters.decreases + 1
        if largeDecrease then
          self.counters.largeDeltas = self.counters.largeDeltas + 1
        end
        context = context or self:_context(mutation)
        self:_important(mutation, context, recordType)
      end
      -- Semantic thresholds and ordinary direct-threat history belong to
      -- relationship_audit. Agent audit only duplicates anomalies.
    end
  end

  if relationshipAuditEmission then
    local audit = relationshipAuditEmission
    local mismatch = false
    for _, field in ipairs(RELATIONSHIP_FIELDS) do
      if field ~= "lastSeenTick" and (audit.current[field] or 0) ~= (after[field] or 0) then
        mismatch = true
      end
    end
    local forensic = self:_forensicEnabled()
    if forensic or mismatch then
      local cross = forensic and richFields()
        or self:_compactRelationshipFields(mutation, before, after, episode)
      add(cross, "relationshipAuditType", audit.type)
      add(cross, "relationshipAuditCause", audit.cause)
      add(cross, "relationshipAuditSuppressed", audit.suppressedUpdates)
      addRelationship(cross, "auditBaseline.", audit.baseline)
      addRelationship(cross, "auditCurrent.", audit.current)
      add(cross, "auditPendingCauses",
        table.concat(audit.pendingCauses or {}, ","))
      if forensic then
        self:_append("RELATIONSHIP_AUDIT_CROSSREF", mutation.tick, cross)
      end
      if mismatch then
        self:_append("RELATIONSHIP_AUDIT_MISMATCH", mutation.tick, cross)
        self.counters.auditMismatches = self.counters.auditMismatches + 1
        context = context or self:_context(mutation)
        self:_important(mutation, context, "RELATIONSHIP_AUDIT_MISMATCH")
      end
    end
  end
  return true
end

function AgentAudit:observeEvent(event)
  if type(event) ~= "table" or event.observerId == nil
    or event.subjectId == nil then return false end
  local token = self:_objectToken(event.relationshipRef)
  if self:_forensicEnabled() then
    local context = self:_context(event)
    local values = event.phase == "POST_EVENT"
      and copyRelationship(event.after) or copyRelationship(event.before)
    local fields = {}
    add(fields, "observer", event.observerId)
    add(fields, "subject", event.subjectId)
    add(fields, "event", event.event)
    add(fields, "producer", event.producer)
    add(fields, "relationshipObject", token)
    addActor(fields, "observer.", context.observer)
    addActor(fields, "subject.", context.subject)
    addRelationship(fields, "canonical.", values)
    self:_append("RELATIONSHIP_" .. tostring(event.phase), event.tick, fields)
  elseif event.phase == "POST_EVENT"
    and event.event == "INVESTIGATION_COMPLETED" then
    local fields = {}
    add(fields, "observer", event.observerId)
    add(fields, "subject", event.subjectId)
    add(fields, "producer", event.producer)
    add(fields, "relationshipObject", token)
    addRelationship(fields, "before.", event.before)
    addRelationship(fields, "after.", event.after)
    self:_append("INVESTIGATION_COMPLETED", event.tick, fields)
  end
  if event.phase == "POST_EVENT" then
    self.importantByPair[pairKey(event.observerId, event.subjectId)] = {
      event = event.event,
      tick = event.tick
    }
  end
  return true
end

function AgentAudit:sample(tick, actors)
  local forensic = self:_forensicEnabled()
  if forensic then
    for actorId, actor in pairs(actors or {}) do
      local sample = {}
      for key, value in pairs(actor) do sample[key] = value end
      sample.tick = tick
      local history = self.histories[actorId] or {}
      self.histories[actorId] = history
      history[#history + 1] = sample
      while #history > self.historyLimit do table.remove(history, 1) end
      if (self.postWindows[actorId] or 0) > 0 then
        local fields = {}
        add(fields, "actor", actorId)
        addActor(fields, "sample.", sample)
        self:_append("AGENT_HISTORY_POST", tick, fields)
        self.postWindows[actorId] = self.postWindows[actorId] - 1
      end
    end
  end

  local ending = {}
  for key, episode in pairs(self.episodes) do
    if tick - episode.lastContactTick > self.separationTicks then
      ending[#ending + 1] = key
    end
  end
  table.sort(ending)
  for _, key in ipairs(ending) do
    local episode = self.episodes[key]
    local fields = {}
    add(fields, "episode", episode.id)
    add(fields, "entityA", episode.entityA)
    add(fields, "entityB", episode.entityB)
    add(fields, "startTick", episode.startTick)
    add(fields, "lastContactTick", episode.lastContactTick)
    add(fields, "endDetectionTick", tick)
    add(fields, "durationTicks", episode.lastContactTick - episode.startTick)
    add(fields, "socialNearbyObservationCount",
      episode.socialNearbyObservationCount)
    add(fields, "entityNearObservationCount",
      episode.entityNearObservationCount)
    add(fields, "minimumDistance", episode.minDistance)
    add(fields, "maximumDistance", episode.maxDistance)
    local aToB = episode.directions[pairKey(episode.entityA, episode.entityB)]
    local bToA = episode.directions[pairKey(episode.entityB, episode.entityA)]
    for _, summary in ipairs({
      { prefix = "aToB.", value = aToB },
      { prefix = "bToA.", value = bToA }
    }) do
      local direction = summary.value
      add(fields, summary.prefix .. "existedAtStart",
        direction.existedAtStart)
      add(fields, summary.prefix .. "createdDuringEpisode",
        direction.createdDuringEpisode)
      add(fields, summary.prefix .. "socialExposureMutationCount",
        direction.socialExposureMutationCount)
      add(fields, summary.prefix .. "relationshipMutationCount",
        direction.relationshipMutationCount)
      addRelationship(fields, summary.prefix .. "start.",
        direction.startValues)
      addRelationship(fields, summary.prefix .. "end.",
        direction.latestValues)
    end
    self:_append("CONTACT_EPISODE_END", tick, fields)
    self.previousEpisodeEnds[key] = {
      endTick = tick,
      lastContactTick = episode.lastContactTick
    }
    self.episodes[key] = nil
    self.counters.contactEpisodesEnded
      = self.counters.contactEpisodesEnded + 1
  end

  if forensic and (not self.lastPeriodicTick
    or tick - self.lastPeriodicTick >= self.periodicTicks) then
    self.lastPeriodicTick = tick
    for actorId, actor in pairs(actors or {}) do
      if (actor.relationshipCount or 0) > 0 then
        local fields = {}
        add(fields, "actor", actorId)
        addActor(fields, "snapshot.", actor)
        add(fields, "relationships", actor.relevantRelationships)
        self:_append("AGENT_PERIODIC_SNAPSHOT", tick, fields)
      end
    end
  end
end

function AgentAudit:flush(tick, force)
  if not force and self.lastFlushTick
    and (tick or 0) - self.lastFlushTick < self.flushIntervalTicks then
    return true
  end
  if type(self.writer) ~= "function" then return false end
  local allSucceeded = true
  for index, segment in ipairs(self.segments) do
    if segment.dirty or (force and index == self.segmentIndex) then
      local bytes = table.concat(segment.records)
      self.counters.agentAuditWriteCalls
        = self.counters.agentAuditWriteCalls + 1
      local ok = pcall(self.writer, segmentKey(self.storageKey, index), bytes)
      if ok then
        self.counters.agentAuditBytesWritten
          = self.counters.agentAuditBytesWritten + #bytes
        segment.dirty = false
        if index < self.segmentIndex then segment.records = {} end
      else
        allSucceeded = false
      end
    end
  end
  if not allSucceeded then
    if not self.writeFailureReported then
      self.counters.writeFailures = self.counters.writeFailures + 1
      self.writeFailureReported = true
    end
    return false
  end
  self.lastFlushTick = tick or 0
  self.writeFailureReported = false
  return true
end

function AgentAudit:snapshot()
  local result = {}
  for key, value in pairs(self.counters) do
    if key == "recordTypes" then
      result.recordTypes = {}
      for recordType, count in pairs(value) do
        result.recordTypes[recordType] = count
      end
    else
      result[key] = value
    end
  end
  result.fileCount = #self.segments
  result.activeFile = segmentKey(self.storageKey, self.segmentIndex)
  result.maxBytes = self.maxBytes
  result.historySamples = self.historyLimit
  result.postSamples = self.postSamples
  result.separationTicks = self.separationTicks
  result.contactSampleTicks = self.contactSampleTicks
  result.periodicTicks = self.periodicTicks
  return result
end

return AgentAudit
