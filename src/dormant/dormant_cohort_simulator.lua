local CircadianSystem = require("src.circadian.circadian_system")
local Relationships = require("src.entities.relationships")
local EcologyPhysiology = require("src.species.ecology_physiology")

local DormantCohortSimulator = {}
local diagnosticSink = nil
local MAX_SEGMENTS = 48
local SECONDS_PER_HOUR = 3600

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

local function emit(event)
  if diagnosticSink then diagnosticSink(event) end
end

local function averageBias(entity, startTime, elapsed)
  if elapsed <= 0 then return 0, 0, 0 end
  local segments = math.min(MAX_SEGMENTS, math.max(1,
    math.ceil(math.min(elapsed, 86400) / 1800)))
  local activity, rest = 0, 0
  for index = 1, segments do
    local sampleTime = startTime + elapsed * ((index - 0.5) / segments)
    local circadian = CircadianSystem.evaluate(entity, (sampleTime % 86400) / 86400)
    activity = activity + circadian.activityBias
    rest = rest + circadian.restBias
  end
  return activity / segments, rest / segments, segments
end

local function hasOpportunity(evidence, driveId, entityId)
  local record = evidence and evidence[driveId] and evidence[driveId][entityId]
  return record and record.proven == true
end

local function updateEnvironmentalDrive(entity, driveId, elapsed, hourlyRate,
  physiologyRate, opportunityProven, simulationTick)
  local drive = entity.drives[driveId]
  if not drive then return nil end
  local before = clamp(drive.value or 0, 0, 1)
  local accumulated = before + elapsed / SECONDS_PER_HOUR
    * hourlyRate * physiologyRate
  local satisfactions = 0
  if opportunityProven and accumulated >= 0.65 then
    satisfactions = math.floor(accumulated / 0.65)
    accumulated = accumulated % 0.65
  end
  drive.value = clamp(accumulated, 0, 1)
  if simulationTick ~= nil then drive.lastUpdatedTick = simulationTick end
  return { before = before, after = drive.value,
    coarseSatisfactions = satisfactions }
end

local function updateDrives(entity, elapsed, activity, rest, opportunityEvidence,
  simulationTick)
  entity.drives = entity.drives or {}
  local hours = elapsed / SECONDS_PER_HOUR
  local updates = {}
  local physiology = EcologyPhysiology.forEntity(entity)

  updates.THIRST = updateEnvironmentalDrive(entity, "THIRST", elapsed, 0.08,
    physiology.thirstRate,
    hasOpportunity(opportunityEvidence, "THIRST", entity.id), simulationTick)
  updates.HUNGER = updateEnvironmentalDrive(entity, "HUNGER", elapsed, 0.06,
    physiology.hungerRate,
    hasOpportunity(opportunityEvidence, "HUNGER", entity.id), simulationTick)

  local fatigue = entity.drives.FATIGUE
  if fatigue then
    local before = clamp(fatigue.value or 0, 0, 1)
    local activeGain = hours * activity * 0.055 * physiology.fatigueRate
    local recovery = hours * rest * 0.11 * physiology.restRecovery
    fatigue.value = clamp(before + activeGain - recovery, 0, 1)
    if simulationTick ~= nil then fatigue.lastUpdatedTick = simulationTick end
    updates.FATIGUE = { before = before, after = fatigue.value }
  end
  return updates
end

local function candidateReason(observer, subject, snapshot, relationship)
  local observerSnapshot = snapshot.memberSnapshots[observer.id] or {}
  local subjectSnapshot = snapshot.memberSnapshots[subject.id] or {}
  if contains(observerSnapshot.closeContacts, subject.id) then
    return "ACTIVE_CONTACT", "HIGH", 1.0
  end
  if observerSnapshot.groupId ~= nil
    and observerSnapshot.groupId == subjectSnapshot.groupId then
    return "SAME_GROUP", "HIGH", 0.85
  end
  if relationship then
    local strength = math.max(relationship.affinity or 0,
      relationship.familiarity or 0) / 100
    return "EXISTING_ASSOCIATION", "MODERATE", 0.35 + strength * 0.35
  end
  return nil
end

local function socialCandidates(cohort, entitiesById)
  local candidates, seen = {}, {}
  local memberSet = {}
  for _, id in ipairs(cohort.memberIds or {}) do memberSet[id] = true end
  for _, observerId in ipairs(cohort.memberIds or {}) do
    local observer = entitiesById[observerId]
    if observer then
      local targets = {}
      local snapshot = cohort.memberSnapshots[observerId] or {}
      for _, targetId in ipairs(snapshot.closeContacts or {}) do targets[targetId] = true end
      for targetId in pairs(observer.relationships or {}) do
        if memberSet[targetId] then targets[targetId] = true end
      end
      if snapshot.groupId ~= nil then
        for _, targetId in ipairs(cohort.memberIds or {}) do
          local targetSnapshot = cohort.memberSnapshots[targetId] or {}
          if targetId ~= observerId and targetSnapshot.groupId == snapshot.groupId then
            targets[targetId] = true
          end
        end
      end
      for targetId in pairs(targets) do
        local key = tostring(observerId) .. ">" .. tostring(targetId)
        if not seen[key] and entitiesById[targetId] then
          candidates[#candidates + 1] = { observer = observer,
            subject = entitiesById[targetId] }
          seen[key] = true
        end
      end
    end
  end
  return candidates
end

local function updateSocial(cohort, entitiesById, elapsed)
  local candidates = socialCandidates(cohort, entitiesById)
  local updates = 0
  for _, pair in ipairs(candidates) do
    local observer, subject = pair.observer, pair.subject
    local existing = observer.relationships and observer.relationships[subject.id]
    local reason, tier, evidence = candidateReason(observer, subject, cohort, existing)
    if reason then
      local overlap = CircadianSystem.overlap(observer, subject, 24)
      local temperament = observer.temperament or {}
      local rawStats = observer.rawStats or {}
      local receptivity = clamp(0.35 + (temperament.sociability or 0.5) * 0.55
        - (rawStats.independence or 0.5) * 0.2, 0.15, 1)
      local hours = elapsed / SECONDS_PER_HOUR
      local exposure = evidence * receptivity
        * (0.25 + overlap.active * 0.65 + overlap.resting * 0.10)
      local relationship = existing or Relationships.getOrCreate(observer, subject.id)
      local beforeFamiliarity = relationship.familiarity or 0
      local beforeAffinity = relationship.affinity or 0
      local saturation = 1 - math.exp(-hours / 24)
      local familiarityGain = 10 * exposure * saturation
      local affinityGain = 3 * exposure * saturation
      relationship.familiarity = clamp(beforeFamiliarity + familiarityGain, 0, 100)
      relationship.affinity = clamp(beforeAffinity + affinityGain, 0, 100)
      updates = updates + 1
      emit({ event = "DORMANT_SOCIAL_UPDATE", entityA = observer.id,
        entityB = subject.id, elapsed = elapsed, estimatedExposure = exposure,
        tier = tier, reason = reason, familiarityBefore = beforeFamiliarity,
        familiarityAfter = relationship.familiarity,
        affinityBefore = beforeAffinity, affinityAfter = relationship.affinity })
    end
  end
  return updates, #candidates
end

function DormantCohortSimulator.setDiagnosticSink(sink)
  diagnosticSink = type(sink) == "function" and sink or nil
end

function DormantCohortSimulator.advance(cohort, entitiesById, nowEcologyTime, options)
  options = options or {}
  local startTime = cohort.lastEcologyTime or nowEcologyTime or 0
  local elapsed = math.max(0, (nowEcologyTime or startTime) - startTime)
  emit({ event = "DORMANT_CATCHUP_START", mapId = cohort.mapId,
    elapsed = elapsed, members = #(cohort.memberIds or {}) })
  local segmentCount, driveUpdates = 0, 0
  for _, entityId in ipairs(cohort.memberIds or {}) do
    local entity = entitiesById[entityId]
    if entity then
      local activity, rest, segments = averageBias(entity, startTime, elapsed)
      segmentCount = math.max(segmentCount, segments)
      local updates = updateDrives(entity, elapsed, activity, rest,
        cohort.environment and cohort.environment.opportunityEvidence or {},
        options.simulationTick)
      for driveId, update in pairs(updates) do
        driveUpdates = driveUpdates + 1
        emit({ event = "DORMANT_DRIVE_UPDATE", actorId = entity.id,
          drive = driveId, elapsed = elapsed, before = update.before,
          after = update.after, coarseSatisfactions = update.coarseSatisfactions })
      end
    end
  end
  local socialUpdates, pairCandidates = updateSocial(cohort, entitiesById, elapsed)
  cohort.lastEcologyTime = math.max(startTime, nowEcologyTime or startTime)
  cohort.catchUpCount = (cohort.catchUpCount or 0) + 1
  cohort.lastCatchUp = { elapsed = elapsed, segments = segmentCount,
    driveUpdates = driveUpdates, socialUpdates = socialUpdates,
    pairCandidates = pairCandidates,
    totalPossibleDirectedPairs = #(cohort.memberIds or {})
      * math.max(0, #(cohort.memberIds or {}) - 1) }
  emit({ event = "DORMANT_CATCHUP_COMPLETE", mapId = cohort.mapId,
    elapsed = elapsed, segments = segmentCount, driveUpdates = driveUpdates,
    socialUpdates = socialUpdates, pairCandidates = pairCandidates })
  return cohort.lastCatchUp
end

DormantCohortSimulator.MAX_SEGMENTS = MAX_SEGMENTS

return DormantCohortSimulator