local Archetypes = require("src.species.archetypes")
local SpeciesEcology = require("src.species.species_ecology")

local Fear = {}
local counters = {
  fearUpdates = 0,
  socialFearAggregations = 0,
  socialSourceEvaluations = 0,
  directFearEvaluations = 0,
  alarmOutputUpdates = 0
}

function Fear.getCounters()
  local copy = {}
  for key, value in pairs(counters) do copy[key] = value end
  return copy
end

function Fear.resetCounters()
  for key in pairs(counters) do counters[key] = 0 end
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function combineBounded(values)
  local remaining = 1
  for _, value in ipairs(values or {}) do
    remaining = remaining * (1 - clamp(value, 0, 1))
  end
  return 1 - remaining
end

local function combineSocialContributions(contributions)
  table.sort(contributions, function(left, right) return left.value > right.value end)
  local strongest = contributions[1] and contributions[1].value or 0
  if strongest <= 0 then return 0 end
  local corroboration = 0
  for index = 2, #contributions do
    corroboration = corroboration + contributions[index].value * 0.18
  end
  return clamp(strongest + corroboration, 0, math.min(0.9, strongest * 1.35))
end

function Fear.susceptibility(entity)
  local speciesEcology = SpeciesEcology.getResolved(entity and entity.species)
  local override = entity and entity.ecology or {}
  local archetype = Archetypes.get(override.archetype or speciesEcology.archetype)
  local configured = override.socialFearSusceptibility
    or speciesEcology.socialFearSusceptibility
  local base = configured ~= nil and configured or archetype.socialFearSusceptibility or 0.4
  local temperament = entity and entity.temperament or {}
  local sociality = temperament.sociability or 0.5
  local independence = entity and entity.rawStats and entity.rawStats.independence or 0.5
  return clamp(base * (0.65 + sociality * 0.5) * (1.2 - independence * 0.4), 0.1, 1)
end

local function alarmProfile(entityOrSource)
  local speciesEcology = SpeciesEcology.getResolved(entityOrSource and entityOrSource.species)
  local override = entityOrSource and entityOrSource.ecology or {}
  local archetype = Archetypes.get(override.archetype or speciesEcology.archetype)
  return {
    broadcast = override.alarmBroadcastStrength
      or speciesEcology.alarmBroadcastStrength or archetype.alarmBroadcastStrength or 0.65,
    conspecific = override.conspecificAlarmSensitivity
      or speciesEcology.conspecificAlarmSensitivity or archetype.conspecificAlarmSensitivity or 0.65,
    heterospecific = override.heterospecificAlarmSensitivity
      or speciesEcology.heterospecificAlarmSensitivity
      or archetype.heterospecificAlarmSensitivity or 0.4
  }
end

function Fear.speciesAlarmCompatibility(observer, source)
  local receiver = alarmProfile(observer)
  local sameSpecies = observer and source and observer.species ~= nil and source.species ~= nil
    and observer.species == source.species
  if source and source.species == nil and source.conspecific ~= nil then
    sameSpecies = source.conspecific == true
  end
  return clamp(sameSpecies and receiver.conspecific or receiver.heterospecific, 0, 1.25), sameSpecies
end

function Fear.directInput(entity, context)
  counters.directFearEvaluations = counters.directFearEvaluations + 1
  local settings = context or {}
  local assessment = settings.threatAssessment
  local activeThreat = assessment and assessment.primaryThreatId ~= nil
    or assessment == nil and settings.threatDistance ~= nil
  if not activeThreat then return 0 end
  local relationship = settings.relationship or {}
  local distance = settings.threatDistance
  local proximity = distance and clamp((6 - distance) / 5, 0, 1) or 0
  local memory = clamp(((relationship.threatMemory or 0) + (relationship.hostility or 0) * 2) / 100, 0, 1)
  local perceived = clamp((settings.perceivedFear or 0) / 20, 0, 1)
  local execution = entity and entity.runtimeState and entity.runtimeState.fleeExecution or {}
  local confinement = execution.escapeMode and 0.18 or 0
  confinement = confinement + clamp((execution.noProgressSteps or 0) * 0.05, 0, 0.2)
  confinement = confinement + clamp((execution.staticRejections or 0) * 0.05, 0, 0.15)
  return clamp(combineBounded({ proximity * 0.72, memory * 0.55, perceived * 0.7, confinement }), 0, 1)
end

function Fear.socialInput(entity, sources, radius)
  counters.socialFearAggregations = counters.socialFearAggregations + 1
  local susceptibility = Fear.susceptibility(entity)
  local contributions = {}
  local strongestId, strongest = nil, 0
  local biasX, biasY, biasWeight = 0, 0, 0
  local count, rawTotal, echoSuppressed = 0, 0, 0
  local conspecificCount, heterospecificCount = 0, 0
  local groundedWeighted, groundedWeight = 0, 0
  local contributionBySource = {}
  local contributionDetails = {}
  local strongestSpecies = nil
  for _, source in ipairs(sources or {}) do
    counters.socialSourceEvaluations = counters.socialSourceEvaluations + 1
    local sourceAlarm = clamp(source.alarmOutput or 0, 0, 1)
    local echoShare = source.socialInputRaw and source.socialInputRaw > 0
      and clamp((source.echoContribution or 0) / source.socialInputRaw, 0, 1)
      or 0
    local echoLoss = clamp((source.alarmRelayedComponent or 0) * echoShare, 0, sourceAlarm)
    local transmissibleAlarm = math.max(0, sourceAlarm - echoLoss)
    local distance = source.distance or math.huge
    local attenuation = clamp(((radius or 5) + 1 - distance) / (radius or 5), 0, 1)
    local visiblePanic = source.state == "FLEE" and 1 or 0.45
    local speciesCompatibility, sameSpecies = Fear.speciesAlarmCompatibility(entity, source)
    local sourceBroadcast = (source.species ~= nil or source.ecology ~= nil)
      and clamp(alarmProfile(source).broadcast, 0, 1.25)
      or 1
    local relationship = source.relationship or {}
    local relationshipScale = source.family and 1.15
      or source.trusted and 1.1
      or ((relationship.trust or 0) >= 20 or (relationship.affinity or 0) >= 20) and 1.05
      or 1
    local provenanceAttenuation = clamp(0.55 + (source.alarmGroundedness or 0) * 0.45, 0.55, 1)
    local scale = attenuation * visiblePanic * susceptibility
      * speciesCompatibility * relationshipScale * provenanceAttenuation * 0.72
    local rawContribution = clamp(sourceAlarm * scale, 0, 0.8)
    local contribution = clamp(transmissibleAlarm * scale, 0, 0.8)
    if contribution > 0 then
      contributions[#contributions + 1] = { id = source.id, value = contribution }
      count = count + 1
      rawTotal = rawTotal + rawContribution
      echoSuppressed = echoSuppressed + math.max(0, rawContribution - contribution)
      contributionBySource[source.id] = contribution
      contributionDetails[#contributionDetails + 1] = {
        sourceId = source.id,
        sourceSpecies = source.species,
        observerSpecies = entity and entity.species or nil,
        sameSpecies = sameSpecies,
        speciesAlarmCompatibility = speciesCompatibility,
        sourceAlarmOutput = sourceAlarm,
        sourceBroadcastStrength = sourceBroadcast,
        distanceAttenuation = attenuation,
        provenanceAttenuation = provenanceAttenuation,
        finalSocialContribution = contribution
      }
      if sameSpecies then conspecificCount = conspecificCount + 1
      else heterospecificCount = heterospecificCount + 1 end
      local groundedness = clamp(source.alarmGroundedness or 0, 0, 1)
      groundedWeighted = groundedWeighted + groundedness * contribution
      groundedWeight = groundedWeight + contribution
      if contribution > strongest then
        strongest, strongestId, strongestSpecies = contribution, source.id, source.species
      end
      if source.escapeBias then
        biasX = biasX + source.escapeBias.dx * contribution * speciesCompatibility
        biasY = biasY + source.escapeBias.dy * contribution * speciesCompatibility
        biasWeight = biasWeight + contribution
      end
    end
  end
  local bias, confidence = nil, 0
  if biasWeight > 0 then
    local magnitude = math.sqrt(biasX * biasX + biasY * biasY)
    confidence = clamp(magnitude / biasWeight, 0, 1)
    if magnitude > 0 then
      bias = { dx = biasX / magnitude, dy = biasY / magnitude }
    end
  end
  local combined = combineSocialContributions(contributions)
  return combined, {
    nearbyFearSources = count,
    conspecificSourceCount = conspecificCount,
    heterospecificSourceCount = heterospecificCount,
    strongestFearSource = strongestId,
    strongestSocialSourceSpecies = strongestSpecies,
    strongestIncomingAlarm = strongest,
    socialInputRaw = rawTotal,
    socialInputAfterRelayLoss = combined,
    echoSuppressedAmount = echoSuppressed,
    incomingGroundedness = groundedWeight > 0 and groundedWeighted / groundedWeight or 0,
    contributionBySource = contributionBySource,
    contributionDetails = contributionDetails,
    escapeBias = bias,
    escapeBiasConfidence = confidence
  }
end

local function updateAlarmEmission(entity, runtime, direct, social, socialDetails)
  counters.alarmOutputUpdates = counters.alarmOutputUpdates + 1
  local broadcast = clamp(alarmProfile(entity).broadcast, 0, 1.25)
  local directComponent = clamp(direct * 0.95 * broadcast, 0, 0.95)
  local incomingGroundedness = clamp(socialDetails.incomingGroundedness or 0, 0, 1)
  local relayGroundedness = incomingGroundedness * 0.65
  local relayedComponent = clamp(social * 0.42 * broadcast * (0.7 + relayGroundedness * 0.3), 0, 0.42)
  local output = combineBounded({ directComponent, relayedComponent })
  local weightedGroundedness = directComponent + relayedComponent > 0
    and (directComponent + relayedComponent * relayGroundedness) / (directComponent + relayedComponent)
    or 0
  runtime.alarmOutput = output
  runtime.alarmDirectComponent = directComponent
  runtime.alarmRelayedComponent = relayedComponent
  runtime.alarmGroundedness = clamp(weightedGroundedness, 0, 1)
end

local function updateSocialEscapeBias(runtime, observedBias, observedConfidence, simulationTick, elapsed)
  local current = runtime.socialEscapeBias
  local confidence = runtime.socialEscapeBiasConfidence or 0
  if observedBias and observedConfidence >= 0.2 then
    local perTickBlend = 0.25 * observedConfidence
    local blend = 1 - (1 - perTickBlend) ^ elapsed
    if current then
      current = {
        dx = current.dx * (1 - blend) + observedBias.dx * blend,
        dy = current.dy * (1 - blend) + observedBias.dy * blend
      }
    else
      current = { dx = observedBias.dx, dy = observedBias.dy }
    end
    confidence = clamp(confidence * (1 - blend) + observedConfidence * blend, 0, 1)
    runtime.socialEscapeBiasUpdatedTick = simulationTick
  elseif current then
    local decay = math.max(0, 1 - elapsed * 0.025)
    current = { dx = current.dx * decay, dy = current.dy * decay }
    confidence = confidence * decay
    if confidence < 0.05 then current = nil end
  end
  runtime.socialEscapeBias = current
  runtime.socialEscapeBiasConfidence = confidence
  runtime.socialEscapeBiasAge = runtime.socialEscapeBiasUpdatedTick
    and math.max(0, (simulationTick or 0) - runtime.socialEscapeBiasUpdatedTick)
    or 0
end

function Fear.update(entity, context, simulationTick)
  counters.fearUpdates = counters.fearUpdates + 1
  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  runtime.fearMetrics = runtime.fearMetrics or {
    fearUpdates = 0,
    socialFearAggregations = 0,
    socialSourceEvaluations = 0,
    directFearEvaluations = 0,
    alarmOutputUpdates = 0
  }
  local metrics = runtime.fearMetrics
  metrics.fearUpdates = metrics.fearUpdates + 1
  metrics.socialFearAggregations = metrics.socialFearAggregations + 1
  metrics.socialSourceEvaluations = metrics.socialSourceEvaluations
    + #(context and context.socialSources or {})
  metrics.directFearEvaluations = metrics.directFearEvaluations + 1
  metrics.alarmOutputUpdates = metrics.alarmOutputUpdates + 1
  local prior = clamp(runtime.fearCurrent or 0, 0, 1)
  local elapsed = math.max(1, (simulationTick or 0) - (runtime.lastFearTick or (simulationTick or 0) - 1))
  local observedDirect = Fear.directInput(entity, context)
  local assessment = context and context.threatAssessment or nil
  local activeThreatId = assessment and assessment.primaryThreatId or nil
  local directlyObserved = activeThreatId ~= nil
    or (assessment == nil and context and context.threatDistance ~= nil)
  local decay = math.min(prior, elapsed * (directlyObserved and 0.008 or 0.01))
  local decayed = math.max(0, prior - decay)
  local direct
  if directlyObserved then
    direct = observedDirect
    runtime.directThreatLastSeenTick = simulationTick
    runtime.lastDirectThreatMemory = context and context.relationship
      and (context.relationship.threatMemory or 0) or 0
  else
    local memoryScale = 1 + clamp((runtime.lastDirectThreatMemory or 0) / 100, 0, 1)
    local age = runtime.directThreatLastSeenTick
      and math.max(0, (simulationTick or 0) - runtime.directThreatLastSeenTick)
      or math.huge
    local recoveryRate = age <= 30 and 0.004 or 0.04
    direct = math.max(0, (runtime.fearDirect or 0) - elapsed * recoveryRate / memoryScale)
  end
  local social, socialDetails = Fear.socialInput(entity, context and context.socialSources, context and context.perceptionRadius or 5)
  local input = combineBounded({ direct, social })
  local riseBlend = 1 - (1 - 0.7) ^ elapsed
  local current = input > decayed
    and clamp(decayed + (input - decayed) * riseBlend, 0, 1)
    or decayed

  runtime.fearCurrent = current
  runtime.fearDirect = direct
  runtime.fearSocial = social
  runtime.fearDecay = decay
  runtime.lastFearTick = simulationTick
  runtime.directThreatId = assessment and assessment.primaryThreatId or nil
  runtime.directThreatLastSeenAge = runtime.directThreatLastSeenTick
    and math.max(0, (simulationTick or 0) - runtime.directThreatLastSeenTick)
    or nil
  runtime.socialAlarmIntensity = social
  runtime.nearbyFearSources = socialDetails.nearbyFearSources
  runtime.conspecificSourceCount = socialDetails.conspecificSourceCount
  runtime.heterospecificSourceCount = socialDetails.heterospecificSourceCount
  runtime.strongestFearSource = socialDetails.strongestFearSource
  runtime.strongestSocialSourceSpecies = socialDetails.strongestSocialSourceSpecies
  runtime.strongestIncomingAlarm = socialDetails.strongestIncomingAlarm
  runtime.socialInputRaw = socialDetails.socialInputRaw
  runtime.socialInputAfterRelayLoss = socialDetails.socialInputAfterRelayLoss
  runtime.echoSuppressedAmount = socialDetails.echoSuppressedAmount
  runtime.socialContributionBySource = socialDetails.contributionBySource
  runtime.socialContributionDetails = socialDetails.contributionDetails
  updateAlarmEmission(entity, runtime, direct, social, socialDetails)
  updateSocialEscapeBias(runtime, socialDetails.escapeBias, socialDetails.escapeBiasConfidence, simulationTick, elapsed)
  return current
end

function Fear.escapeDistances(baseRadius, fear, directFear, socialFear, groundedness)
  local base = clamp(baseRadius or 1, 1, 8)
  local current = clamp(fear or 0, 0, 1)
  local direct = clamp(directFear ~= nil and directFear or current, 0, 1)
  local social = clamp(socialFear or 0, 0, 1)
  local socialAuthority = 0.45 + clamp(groundedness or 0, 0, 1) * 0.25
  local effective = clamp(combineBounded({ direct, social * socialAuthority }), 0, 1)
  local trigger = clamp(base + math.floor(effective * 3 + 0.5), 1, 10)
  local safety = clamp(base + math.floor(effective * 5 + 0.5), trigger, 12)
  return trigger, safety
end

function Fear.escapeUrgency(entity, threatDistance)
  local runtime = entity and entity.runtimeState or {}
  local fear = runtime.fearCurrent or 0
  local proximity = threatDistance and 1 / math.max(1, threatDistance) or 0
  local execution = runtime.fleeExecution or {}
  local stalled = (execution.noProgressSteps or 0) + (execution.crowdBlocks or 0)
  local confined = runtime.fleeExecution and runtime.fleeExecution.escapeMode and 0.2 or 0
  return clamp(fear * 0.65 + proximity * 0.2 + math.min(stalled, 30) / 150 + confined, 0, 1)
end

local function fearBand(value)
  local fear = value or 0
  if fear >= 0.85 then return "EMERGENCY" end
  if fear >= 0.7 then return "HIGH" end
  if fear >= 0.22 then return "ACTIVE" end
  if fear >= 0.12 then return "RECOVERY" end
  if fear > 0.005 then return "TRACE" end
  return "CALM"
end

local function sourceBand(count)
  if (count or 0) <= 0 then return "NONE" end
  if count == 1 then return "ONE" end
  return "MULTIPLE"
end

local function balanceBand(runtime)
  local direct = runtime.fearDirect or 0
  local social = runtime.fearSocial or 0
  if direct < 0.05 and social < 0.05 then return "CALM" end
  if direct >= social * 1.5 then return "DIRECT" end
  if social >= direct * 1.5 then return "SOCIAL" end
  return "MIXED"
end

function Fear.diagnosticEvent(runtimeState, trace)
  local runtime = runtimeState or {}
  local current = {
    fear = runtime.fearCurrent or 0,
    direct = runtime.fearDirect or 0,
    social = runtime.fearSocial or 0,
    urgency = runtime.escapeUrgency or 0,
    groundedness = runtime.alarmGroundedness or 0,
    threatId = runtime.directThreatId,
    threatReason = runtime.threatAssessment and runtime.threatAssessment.primaryThreatReason or nil,
    fearBand = fearBand(runtime.fearCurrent),
    sourceBand = sourceBand(runtime.nearbyFearSources),
    balanceBand = balanceBand(runtime),
    strongestSource = (runtime.fearSocial or 0) >= 0.05 and runtime.strongestFearSource or nil,
    state = runtime.state
  }
  local previous = runtime.fearDiagnosticSnapshot
  local lastEmission = runtime.fearDiagnosticEmissionSnapshot
  runtime.fearDiagnosticSnapshot = current
  if trace then
    runtime.fearDiagnosticEmissionSnapshot = current
    return "TRACE"
  end
  if not previous then
    if current.fearBand ~= "CALM" then
      runtime.fearDiagnosticEmissionSnapshot = current
      return "INITIAL_ACTIVE"
    end
    return nil
  end
  local reason
  if previous.threatId ~= current.threatId then reason = "DIRECT_THREAT_CHANGED"
  elseif previous.threatReason ~= current.threatReason then reason = "THREAT_PROVENANCE_CHANGED"
  elseif previous.fearBand ~= current.fearBand then reason = "FEAR_BAND_CHANGED"
  elseif previous.balanceBand ~= current.balanceBand then reason = "FEAR_BALANCE_CHANGED"
  elseif previous.sourceBand ~= current.sourceBand then reason = "SOCIAL_SOURCE_BAND_CHANGED"
  elseif previous.strongestSource ~= current.strongestSource then reason = "STRONGEST_SOURCE_CHANGED"
  end
  if previous.state ~= current.state
    and (previous.state == "FLEE" or current.state == "FLEE") then
    reason = reason or "FLEE_STATE_CHANGED"
  end
  local baseline = lastEmission or previous
  if not reason and (math.abs(current.fear - baseline.fear) >= 0.05
    or math.abs(current.direct - baseline.direct) >= 0.05
    or math.abs(current.social - baseline.social) >= 0.05
    or math.abs(current.urgency - baseline.urgency) >= 0.05) then
    reason = "MEANINGFUL_DELTA"
  end
  if not reason and math.abs(current.groundedness - baseline.groundedness) >= 0.1 then
    reason = "GROUNDEDNESS_DELTA"
  end
  if reason then runtime.fearDiagnosticEmissionSnapshot = current end
  return reason
end

return Fear