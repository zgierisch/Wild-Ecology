local ThreatAssessment = {}

local DEFAULT_SWITCH_MARGIN = 3

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function trainerWariness(entity, candidate)
  if candidate.kind ~= "trainer" then return nil end
  local relationship = candidate.relationship or {}
  local radius = candidate.trainerWarinessRadius
    or (entity.ecology and entity.ecology.trainerWarinessRadius)
    or 4
  local distance = candidate.distance
  local distanceComponent = distance and distance <= radius
    and clamp((radius + 1 - distance) / radius, 0, 1) * 40
    or 0
  local motion = candidate.motion or "STABLE"
  local motionRelevant = distance ~= nil and distance <= radius + 1
  local approachComponent = motionRelevant and motion == "APPROACHING" and 20
    or motionRelevant and motion == "RETREATING" and -15
    or 0
  local comfort = (relationship.trust or 0) * 0.45
    + (relationship.familiarity or 0) * 0.25
    + (relationship.affinity or 0) * 0.15
  local relationshipModifier = clamp(1 - comfort / 85, 0.05, 1)
  local temperament = entity.temperament or {}
  local rawStats = entity.rawStats or {}
  local temperamentModifier = 1
    + (1 - clamp(temperament.boldness or 0.5, 0, 1)) * 0.2
    + (1 - clamp(rawStats.independence or 0.5, 0, 1)) * 0.1
  local score = math.max(0, (distanceComponent + approachComponent)
    * relationshipModifier * temperamentModifier)
  return {
    applicable = distanceComponent > 0 or approachComponent > 0,
    score = score,
    distanceComponent = distanceComponent,
    approachComponent = approachComponent,
    relationshipModifier = relationshipModifier,
    temperamentModifier = temperamentModifier,
    motion = motion,
    familiarity = relationship.familiarity or 0,
    trust = relationship.trust or 0,
    affinity = relationship.affinity or 0
  }
end

local function classify(entity, candidate)
  local relationship = candidate.relationship or {}
  local severity = candidate.directThreatSeverity or 0
  if severity > 0 then
    return severity * 100 + (relationship.hostility or 0), "HIGH_SEVERITY_EVENT", true
  end
  if (relationship.hostility or 0) > 0 then
    return relationship.hostility, "HOSTILITY", false
  end
  if (relationship.directThreatMemory or 0) > 0 then
    return relationship.directThreatMemory, "DIRECT_THREAT_MEMORY", false
  end
  local trainer = trainerWariness(entity, candidate)
  if trainer and trainer.score >= 6 then
    return trainer.score, "TRAINER_WARINESS", false, trainer
  end
  if candidate.threateningApproach then
    return math.max(candidate.approachSeverity or 1, 1), "THREATENING_APPROACH", false
  end
  return nil, nil, false, trainer
end

local function better(left, right)
  if not right then return true end
  if left.score ~= right.score then return left.score > right.score end
  return tostring(left.id) < tostring(right.id)
end

function ThreatAssessment.assess(entity, candidates, simulationTick, options)
  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  local prior = runtime.threatAssessment or {}
  local identified = {}
  local byId = {}
  local trainerDiagnostic = nil

  for _, candidate in ipairs(candidates or {}) do
    local score, reason, severe, trainer = classify(entity, candidate)
    if trainer and (not trainerDiagnostic or trainer.score > trainerDiagnostic.score) then
      trainerDiagnostic = trainer
      trainerDiagnostic.id = candidate.id
      trainerDiagnostic.kind = candidate.kind
    end
    if score and score > 0 then
      local identifiedThreat = {
        id = candidate.id,
        score = score,
        reason = reason,
        severe = severe,
        distance = candidate.distance,
        relationship = candidate.relationship,
        persistentThreatMemoryWritten = candidate.persistentThreatMemoryWritten == true,
        persistentThreatMemoryReason = candidate.persistentThreatMemoryReason
      }
      if trainer then identifiedThreat.trainerWariness = trainer end
      identified[#identified + 1] = identifiedThreat
      byId[candidate.id] = identifiedThreat
    end
  end

  local strongest = nil
  for _, threat in ipairs(identified) do
    if better(threat, strongest) then strongest = threat end
  end

  local current = prior.primaryThreatId and byId[prior.primaryThreatId] or nil
  local selected = strongest
  local switchMargin = options and options.switchMargin or DEFAULT_SWITCH_MARGIN
  local switched = false
  local switchReason = "NONE"
  if current and strongest and strongest.id ~= current.id then
    if strongest.severe then
      switchReason = "HIGH_SEVERITY_EVENT"
    elseif strongest.score >= current.score + switchMargin then
      switchReason = "SCORE_MARGIN"
    else
      selected = current
      switchReason = "BELOW_MARGIN"
    end
  elseif current then
    selected = current
  elseif strongest then
    switchReason = prior.primaryThreatId and "PRIOR_NO_LONGER_IDENTIFIED" or "INITIAL_THREAT"
  elseif prior.primaryThreatId then
    switchReason = "NO_IDENTIFIED_THREAT"
  end

  if selected and prior.primaryThreatId and selected.id ~= prior.primaryThreatId then
    switched = true
  end
  local primarySinceTick = selected and selected.id == prior.primaryThreatId
    and (prior.primaryThreatSinceTick or simulationTick)
    or simulationTick
  local challenger = strongest and selected and strongest.id ~= selected.id and strongest or nil
  local assessment = {
    previousPrimaryThreatId = prior.primaryThreatId,
    primaryThreatId = selected and selected.id or nil,
    primaryThreatScore = selected and selected.score or 0,
    primaryThreatReason = selected and selected.reason or "NONE",
    primaryThreatSevere = selected and selected.severe == true or false,
    primaryThreatAge = selected and math.max(0, (simulationTick or 0) - (primarySinceTick or 0)) or 0,
    primaryThreatSinceTick = primarySinceTick,
    primaryThreatDistance = selected and selected.distance or nil,
    primaryThreatRelationship = selected and selected.relationship or nil,
    challengerThreatId = challenger and challenger.id or nil,
    challengerScore = challenger and challenger.score or 0,
    switchMargin = switchMargin,
    threatSwitch = switched,
    threatSwitchReason = switchReason,
    identifiedThreatCount = #identified,
    identifiedThreats = identified
  }
  assessment.targetId = trainerDiagnostic and trainerDiagnostic.id or nil
  assessment.targetKind = trainerDiagnostic and trainerDiagnostic.kind or nil
  assessment.trainerWarinessApplicable = trainerDiagnostic and trainerDiagnostic.applicable or false
  assessment.trainerThreatScore = trainerDiagnostic and trainerDiagnostic.score or 0
  assessment.trainerThreatDistanceComponent = trainerDiagnostic and trainerDiagnostic.distanceComponent or 0
  assessment.trainerThreatApproachComponent = trainerDiagnostic and trainerDiagnostic.approachComponent or 0
  assessment.trainerThreatRelationshipModifier = trainerDiagnostic and trainerDiagnostic.relationshipModifier or 0
  assessment.trainerRelationshipFamiliarity = trainerDiagnostic and trainerDiagnostic.familiarity or 0
  assessment.trainerRelationshipTrust = trainerDiagnostic and trainerDiagnostic.trust or 0
  assessment.trainerRelationshipAffinity = trainerDiagnostic and trainerDiagnostic.affinity or 0
  assessment.persistentThreatMemoryWritten = selected
    and selected.persistentThreatMemoryWritten == true or false
  assessment.persistentThreatMemoryReason = selected and selected.persistentThreatMemoryReason
    or trainerDiagnostic and "TRANSIENT_TRAINER_WARINESS" or "NONE"
  runtime.threatAssessment = assessment
  runtime.directThreatId = assessment.primaryThreatId
  return assessment
end

return ThreatAssessment