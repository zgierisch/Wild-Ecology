local ActivityProfiles = require("src.circadian.activity_profiles")
local SpeciesEcology = require("src.species.species_ecology")

local CircadianSystem = {}
local MIX_MODULUS = 67108864

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function circularDistance(left, right)
  local distance = math.abs(left - right) % 1
  return math.min(distance, 1 - distance)
end

local function smoothstep(value)
  local x = clamp(value, 0, 1)
  return x * x * (3 - 2 * x)
end

local function identityUnit(seed, salt)
  local reduced = math.abs(math.floor(seed or 0)) % MIX_MODULUS
  local mixed = (reduced * 40503199 + salt * 40503) % MIX_MODULUS
  return ((mixed * 26146329 + 12345) % MIX_MODULUS) / (MIX_MODULUS - 1)
end

function CircadianSystem.ensure(entity, profileId)
  entity.ecology = entity.ecology or {}
  entity.ecology.activityProfile = entity.ecology.activityProfile
    or profileId or SpeciesEcology.resolve(entity.species).activityProfile
  entity.ecology.circadian = entity.ecology.circadian or {}
  local circadian = entity.ecology.circadian
  if circadian.phaseOffset == nil then
    circadian.phaseOffset = (identityUnit(entity.personalitySeed, 211) - 0.5) * 0.08
  end
  if circadian.amplitudeScale == nil then
    circadian.amplitudeScale = 0.92 + identityUnit(entity.personalitySeed, 223) * 0.16
  end
  return circadian
end

function CircadianSystem.evaluate(entity, phase, profileOverride)
  local resolvedProfile = profileOverride or entity.ecology
    and entity.ecology.activityProfile
    or SpeciesEcology.resolve(entity.species).activityProfile
  local circadian = CircadianSystem.ensure(entity, resolvedProfile)
  local profile = ActivityProfiles.get(resolvedProfile)
  local shiftedPhase = ((phase or 0) + circadian.phaseOffset) % 1
  local peakSignal = 0
  for _, peak in ipairs(profile.peaks or {}) do
    local width = math.max(0.001, peak.width or profile.transitionWidth or 0.1)
    local signal = 1 - smoothstep(circularDistance(shiftedPhase, peak.phase) / width)
    peakSignal = math.max(peakSignal, signal * (peak.weight or 1))
  end
  local activity = clamp((profile.baseline or 0)
    + peakSignal * (profile.activityAmplitude or 1) * circadian.amplitudeScale, 0, 1)
  local rest = clamp((1 - activity) * (profile.restAmplitude or 1), 0, 1)
  return {
    profile = profile.id,
    phase = shiftedPhase,
    phaseOffset = circadian.phaseOffset,
    amplitudeScale = circadian.amplitudeScale,
    activityBias = activity,
    restBias = rest
  }
end

function CircadianSystem.overlap(left, right, segments)
  local count = math.max(4, segments or 24)
  local active, resting = 0, 0
  for index = 0, count - 1 do
    local phase = (index + 0.5) / count
    local leftBias = CircadianSystem.evaluate(left, phase)
    local rightBias = CircadianSystem.evaluate(right, phase)
    active = active + math.min(leftBias.activityBias, rightBias.activityBias)
    resting = resting + math.min(leftBias.restBias, rightBias.restBias)
  end
  return { active = active / count, resting = resting / count }
end

function CircadianSystem.inspect(entity, phase)
  local result = CircadianSystem.evaluate(entity, phase)
  return string.format(
    "CIRCADIAN actor=%s profile=%s offset=%.4f activity=%.3f rest=%.3f",
    tostring(entity and entity.id or "none"), result.profile,
    result.phaseOffset, result.activityBias, result.restBias)
end

return CircadianSystem