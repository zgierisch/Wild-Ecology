local RelationshipAudit = {}
RelationshipAudit.__index = RelationshipAudit

local DEFAULT_MAX_BYTES = 196 * 1024
local DEFAULT_FLUSH_INTERVAL_TICKS = 30
local STORAGE_KEY = "relationship_audit"

local AUDIT_FIELDS = {
  "familiarity", "trust", "affinity", "threatMemory",
  "directThreatMemory", "hostility"
}

local THRESHOLDS = {
  familiarity = { 10, 25, 50, 60, 75, 100 },
  trust = { 20, 25, 40, 50, 75, 100 },
  affinity = { 10, 20, 25, 50, 75, 100 },
  threatMemory = { 10, 25, 50, 75, 100 }
}

local MILESTONE_TYPES = {
  familiarity = "FAMILIARITY_MILESTONE",
  trust = "TRUST_MILESTONE",
  affinity = "AFFINITY_MILESTONE",
  threatMemory = "THREAT_MILESTONE"
}

local function copySnapshot(snapshot)
  local result = {}
  for _, field in ipairs(AUDIT_FIELDS) do
    result[field] = snapshot and snapshot[field] or 0
  end
  return result
end

local function crossedThresholds(oldValue, newValue, thresholds)
  local old = oldValue or 0
  local new = newValue or 0
  local crossed = {}
  for _, threshold in ipairs(thresholds or {}) do
    if (old < threshold and new >= threshold)
      or (old >= threshold and new < threshold) then
      crossed[#crossed + 1] = threshold
    end
  end
  return crossed
end

local function formatNumber(value)
  if type(value) ~= "number" then return tostring(value) end
  if value == math.floor(value) then return tostring(value) end
  return string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", "")
end

local function sanitize(value)
  return tostring(value or "none"):gsub("[\t\r\n]", " ")
end

local function storageKeyForSegment(baseKey, segmentIndex)
  if segmentIndex == 1 then return baseKey end
  return baseKey .. "_" .. tostring(segmentIndex)
end

local function newSegment()
  return { records = {}, textBytes = 0, dirty = false }
end

local function addSnapshot(parts, snapshot)
  for _, field in ipairs(AUDIT_FIELDS) do
    parts[#parts + 1] = field .. "=" .. formatNumber(snapshot[field] or 0)
  end
end

function RelationshipAudit.new(options)
  local settings = options or {}
  local audit = setmetatable({
    maxBytes = settings.maxBytes or DEFAULT_MAX_BYTES,
    flushIntervalTicks = settings.flushIntervalTicks
      or DEFAULT_FLUSH_INTERVAL_TICKS,
    storageKey = settings.storageKey or STORAGE_KEY,
    writer = settings.writer,
    epochStartTick = settings.epochStartTick,
    segments = { newSegment() },
    activeSegmentIndex = 1,
    nextSequence = 1,
    lastFlushTick = nil,
    writeFailureReported = false,
    counters = {
      relationshipAuditMutationsObserved = 0,
      relationshipAuditRecordsWritten = 0,
      relationshipAuditMinorUpdatesSuppressed = 0,
      relationshipAuditCreationRecords = 0,
      relationshipAuditThreatRecords = 0,
      relationshipAuditMilestoneRecords = 0,
      relationshipAuditBytesWritten = 0,
      relationshipAuditWriteCalls = 0,
      relationshipAuditFileSize = 0,
      relationshipAuditDroppedRecords = 0,
      relationshipAuditFileRotations = 0,
      relationshipAuditWriteFailures = 0,
      relationshipAuditRecordsByEvent = {}
    }
  }, RelationshipAudit)
  if audit.epochStartTick ~= nil then
    audit:_append({
      "v=2", "tick=" .. sanitize(audit.epochStartTick),
      "type=AUDIT_EPOCH_START",
      "auditEpochStartTick=" .. sanitize(audit.epochStartTick)
    }, "AUDIT_EPOCH_START")
  end
  return audit
end

function RelationshipAudit:_append(parts, category)
  table.insert(parts, 2, "seq=" .. tostring(self.nextSequence))
  self.nextSequence = self.nextSequence + 1
  local framed = table.concat(parts, "\t") .. "\n"
  if #framed > self.maxBytes then
    self.counters.relationshipAuditDroppedRecords
      = self.counters.relationshipAuditDroppedRecords + 1
    return false
  end
  local segment = self.segments[self.activeSegmentIndex]
  if segment.textBytes + #framed > self.maxBytes then
    self.activeSegmentIndex = self.activeSegmentIndex + 1
    segment = newSegment()
    self.segments[self.activeSegmentIndex] = segment
    self.counters.relationshipAuditFileRotations
      = self.counters.relationshipAuditFileRotations + 1
  end
  segment.records[#segment.records + 1] = framed
  segment.textBytes = segment.textBytes + #framed
  segment.dirty = true
  self.counters.relationshipAuditRecordsWritten
    = self.counters.relationshipAuditRecordsWritten + 1
  self.counters.relationshipAuditFileSize = segment.textBytes
  local byEvent = self.counters.relationshipAuditRecordsByEvent
  byEvent[category] = (byEvent[category] or 0) + 1
  return true
end

function RelationshipAudit:_descriptor(category, mutation, before, current)
  return {
    type = category,
    cause = mutation.event,
    baseline = copySnapshot(before),
    current = copySnapshot(current),
    pendingCauses = {},
    suppressedUpdates = 0
  }
end

function RelationshipAudit:_emitMilestone(category, mutation, field,
  thresholds, direction, before, current)
  local parts = {
    "v=2",
    "tick=" .. sanitize(mutation.tick),
    "type=" .. category,
    "observer=" .. sanitize(mutation.observerId),
    "subject=" .. sanitize(mutation.subjectId),
    "cause=" .. sanitize(mutation.event),
    "field=" .. field,
    "thresholds=" .. table.concat(thresholds, ","),
    "direction=" .. direction
  }
  addSnapshot(parts, current)
  self:_append(parts, category)
  return self:_descriptor(category, mutation, before, current)
end

function RelationshipAudit:_emitAtomic(category, mutation, before, current)
  local parts = {
    "v=2",
    "tick=" .. sanitize(mutation.tick),
    "type=" .. category,
    "observer=" .. sanitize(mutation.observerId),
    "subject=" .. sanitize(mutation.subjectId),
    "cause=" .. sanitize(mutation.event)
  }
  for _, field in ipairs(AUDIT_FIELDS) do
    local oldValue = before[field] or 0
    local newValue = current[field] or 0
    if oldValue ~= newValue then
      parts[#parts + 1] = field .. "=" .. formatNumber(oldValue)
        .. "->" .. formatNumber(newValue)
    end
  end
  self:_append(parts, category)
  return self:_descriptor(category, mutation, before, current)
end

function RelationshipAudit:observe(mutation)
  if type(mutation) ~= "table" or mutation.observerId == nil
    or mutation.subjectId == nil then
    return false
  end
  if self.epochStartTick ~= nil and type(mutation.tick) == "number"
    and mutation.tick < self.epochStartTick then
    return false
  end
  self.counters.relationshipAuditMutationsObserved
    = self.counters.relationshipAuditMutationsObserved + 1

  local before = copySnapshot(mutation.before)
  local current = copySnapshot(mutation.relationship)
  if mutation.created == true then
    local parts = {
      "v=2", "tick=" .. sanitize(mutation.tick),
      "type=RELATIONSHIP_CREATED",
      "observer=" .. sanitize(mutation.observerId),
      "subject=" .. sanitize(mutation.subjectId),
      "cause=" .. sanitize(mutation.event)
    }
    addSnapshot(parts, current)
    self:_append(parts, "RELATIONSHIP_CREATED")
    self.counters.relationshipAuditCreationRecords
      = self.counters.relationshipAuditCreationRecords + 1
    return true, self:_descriptor("RELATIONSHIP_CREATED", mutation, before,
      current)
  end

  if before.directThreatMemory ~= current.directThreatMemory then
    local category = before.directThreatMemory <= 0
      and current.directThreatMemory > 0 and "DIRECT_THREAT_LEARNED"
      or "DIRECT_THREAT_MEMORY_CHANGED"
    local emission = self:_emitAtomic(category, mutation, before, current)
    self.counters.relationshipAuditThreatRecords
      = self.counters.relationshipAuditThreatRecords + 1
    return true, emission
  end
  if before.hostility ~= current.hostility then
    return true, self:_emitAtomic("HOSTILITY_CHANGED", mutation, before,
      current)
  end

  local firstEmission = nil
  local emitted = false
  for _, field in ipairs({ "familiarity", "trust", "affinity",
    "threatMemory" }) do
    local thresholds = crossedThresholds(before[field], current[field],
      THRESHOLDS[field])
    if #thresholds > 0 then
      local direction = (current[field] or 0) > (before[field] or 0)
        and "crossedUp" or "crossedDown"
      local emission = self:_emitMilestone(MILESTONE_TYPES[field], mutation,
        field, thresholds, direction, before, current)
      firstEmission = firstEmission or emission
      emitted = true
      self.counters.relationshipAuditMilestoneRecords
        = self.counters.relationshipAuditMilestoneRecords + 1
    end
  end
  if emitted then return true, firstEmission end

  self.counters.relationshipAuditMinorUpdatesSuppressed
    = self.counters.relationshipAuditMinorUpdatesSuppressed + 1
  return false
end

function RelationshipAudit:flush(tick, force)
  local currentTick = tick or 0
  if not force and self.lastFlushTick
    and currentTick - self.lastFlushTick < self.flushIntervalTicks then
    return true
  end
  if type(self.writer) ~= "function" then return false end
  local allSucceeded = true
  for segmentIndex, segment in ipairs(self.segments) do
    if segment.dirty or (force and segmentIndex == self.activeSegmentIndex) then
      local bytes = table.concat(segment.records)
      self.counters.relationshipAuditWriteCalls
        = self.counters.relationshipAuditWriteCalls + 1
      local ok = pcall(self.writer,
        storageKeyForSegment(self.storageKey, segmentIndex), bytes)
      if ok then
        self.counters.relationshipAuditBytesWritten
          = self.counters.relationshipAuditBytesWritten + #bytes
        segment.dirty = false
        if segmentIndex < self.activeSegmentIndex then segment.records = {} end
      else
        allSucceeded = false
      end
    end
  end
  if not allSucceeded then
    if not self.writeFailureReported then
      self.counters.relationshipAuditWriteFailures
        = self.counters.relationshipAuditWriteFailures + 1
      self.writeFailureReported = true
    end
    return false
  end
  self.lastFlushTick = currentTick
  self.writeFailureReported = false
  return true
end

function RelationshipAudit:snapshot()
  local result = {}
  for key, value in pairs(self.counters) do
    if key == "relationshipAuditRecordsByEvent" then
      local byEvent = {}
      for event, count in pairs(value) do byEvent[event] = count end
      result[key] = byEvent
    else
      result[key] = value
    end
  end
  result.relationshipAuditMaxBytes = self.maxBytes
  result.relationshipAuditStorageKey = self.storageKey
  result.relationshipAuditActiveFile = storageKeyForSegment(
    self.storageKey, self.activeSegmentIndex)
  result.relationshipAuditFileCount = #self.segments
  return result
end

return RelationshipAudit
