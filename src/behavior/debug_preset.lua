local BehaviorDebugPreset = {}

local function copyTable(source)
  local copy = {}
  for key, value in pairs(source or {}) do copy[key] = value end
  return copy
end

local function normalizedName(name)
  if not name then return nil end
  local normalized = tostring(name):upper():gsub("^FORCE_", "")
  if normalized == "TARGET" then return "TARGET" end
  if normalized == "APPROACH" then return "APPROACH" end
  if normalized == "INVESTIGATE" then return "INVESTIGATE" end
  if normalized == "FLEE" then return "FLEE" end
  if normalized == "IDLE" then return "IDLE" end
  return nil
end

local function modelEntity(entity)
  local model = copyTable(entity)
  model.temperament = copyTable(entity and entity.temperament)
  model.rawStats = copyTable(entity and entity.rawStats)
  model.ecology = copyTable(entity and entity.ecology)
  return model
end

local function inputSnapshot(entity, candidate, relationship)
  local temperament = entity and entity.temperament or {}
  local rawStats = entity and entity.rawStats or {}
  return {
    familiarity = relationship and relationship.familiarity or 0,
    trust = relationship and relationship.trust or 0,
    affinity = relationship and relationship.affinity or 0,
    threatMemory = relationship and relationship.threatMemory or 0,
    directThreatMemory = relationship and relationship.directThreatMemory or 0,
    hostility = relationship and relationship.hostility or 0,
    curiosity = temperament.curiosity or 0,
    boldness = temperament.boldness or 0,
    independence = rawStats.independence or 0,
    motion = candidate and candidate.motion or "STABLE"
  }
end

function BehaviorDebugPreset.apply(name, entity, candidate, relationship)
  local preset = normalizedName(name)
  local result = {
    name = preset,
    entity = modelEntity(entity),
    candidate = copyTable(candidate),
    relationship = copyTable(relationship),
    replacedInputs = {},
    socialSources = nil,
    hasTarget = true,
    purposefulTarget = true
  }
  result.originalInputs = inputSnapshot(entity, candidate, relationship)
  result.candidate.relationship = result.relationship
  if not preset then
    result.adjustedInputs = inputSnapshot(result.entity, result.candidate, result.relationship)
    return result
  end

  if preset == "APPROACH" then
    result.relationship.familiarity = 95
    result.relationship.trust = 90
    result.relationship.affinity = 85
    result.relationship.threatMemory = 0
    result.relationship.directThreatMemory = 0
    result.relationship.hostility = 0
    result.entity.temperament.curiosity = 1
    result.entity.temperament.boldness = 0.9
    result.candidate.motion = "STABLE"
    result.fearCurrent = 0
    result.fearDirect = 0
    result.fearSocial = 0
    result.socialSources = {}
    result.novelty = 5
    result.allowTargeting = false
    result.replacedInputs = {
      "relationship.familiarity", "relationship.trust", "relationship.affinity",
      "relationship.threatMemory", "relationship.directThreatMemory", "relationship.hostility",
      "temperament.curiosity", "temperament.boldness", "candidate.motion",
      "fearCurrent", "fearDirect", "fearSocial", "socialSources"
    }
  elseif preset == "FLEE" then
    result.relationship.familiarity = 0
    result.relationship.trust = 0
    result.relationship.affinity = 0
    result.relationship.threatMemory = 20
    result.relationship.directThreatMemory = 0
    result.relationship.hostility = 0
    result.entity.temperament.boldness = 0.1
    result.entity.rawStats.independence = 0.2
    result.candidate.motion = "APPROACHING"
    result.fearCurrent = 0.9
    result.fearDirect = 0.85
    result.fearSocial = 0
    result.socialSources = {}
    result.novelty = 100
    result.replacedInputs = {
      "relationship.familiarity", "relationship.trust", "relationship.affinity",
      "relationship.threatMemory", "relationship.directThreatMemory", "relationship.hostility",
      "temperament.boldness", "rawStats.independence", "candidate.motion",
      "fearCurrent", "fearDirect", "fearSocial", "socialSources"
    }
  elseif preset == "INVESTIGATE" then
    result.relationship.familiarity = 10
    result.relationship.trust = 15
    result.relationship.affinity = 0
    result.relationship.threatMemory = 0
    result.relationship.directThreatMemory = 0
    result.relationship.hostility = 0
    result.entity.temperament.curiosity = 1
    result.entity.temperament.boldness = 1
    result.candidate.motion = "RETREATING"
    result.fearCurrent = 0
    result.fearDirect = 0
    result.fearSocial = 0
    result.socialSources = {}
    result.novelty = 90
    result.allowTargeting = false
    result.replacedInputs = {
      "relationship.familiarity", "relationship.trust", "relationship.affinity",
      "relationship.threatMemory", "relationship.directThreatMemory", "relationship.hostility",
      "temperament.curiosity", "temperament.boldness", "candidate.motion",
      "fearCurrent", "fearDirect", "fearSocial", "socialSources"
    }
  elseif preset == "IDLE" then
    result.relationship.threatMemory = 0
    result.relationship.directThreatMemory = 0
    result.relationship.hostility = 0
    result.entity.temperament.curiosity = 0
    result.fearCurrent = 0
    result.fearDirect = 0
    result.fearSocial = 0
    result.socialSources = {}
    result.hasTarget = false
    result.purposefulTarget = false
    result.allowTargeting = false
    result.replacedInputs = {
      "relationship.threatMemory", "relationship.directThreatMemory", "relationship.hostility",
      "temperament.curiosity", "fearCurrent", "fearDirect", "fearSocial", "socialSources",
      "hasTarget", "purposefulTarget", "allowTargeting"
    }
  elseif preset == "TARGET" then
    result.relationship.threatMemory = 0
    result.relationship.directThreatMemory = 0
    result.relationship.hostility = 0
    result.entity.temperament.curiosity = 0
    result.fearCurrent = 0
    result.fearDirect = 0
    result.fearSocial = 0
    result.socialSources = {}
    result.hasTarget = false
    result.purposefulTarget = false
    result.settledElapsed = 300
    result.replacedInputs = {
      "relationship.threatMemory", "relationship.directThreatMemory", "relationship.hostility",
      "temperament.curiosity", "fearCurrent", "fearDirect", "fearSocial", "socialSources",
      "hasTarget", "purposefulTarget", "settledElapsed"
    }
  end

  result.candidate.relationship = result.relationship
  result.adjustedInputs = inputSnapshot(result.entity, result.candidate, result.relationship)
  result.adjustedInputs.fearCurrent = result.fearCurrent
  result.adjustedInputs.fearDirect = result.fearDirect
  result.adjustedInputs.fearSocial = result.fearSocial
  result.adjustedInputs.hasTarget = result.hasTarget
  result.adjustedInputs.purposefulTarget = result.purposefulTarget
  result.adjustedInputs.idleElapsed = result.idleElapsed
  result.adjustedInputs.settledElapsed = result.settledElapsed
  return result
end

return BehaviorDebugPreset
