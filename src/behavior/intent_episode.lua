local Utility = require("src.behavior.utility")
local Motivation = require("src.behavior.motivation")
local Drives = require("src.needs.drives")
local FoodOpportunities = require("src.needs.food_opportunities")
local SpatialGoal = require("src.behavior.spatial_goal")

local IntentEpisode = {}

local PURPOSEFUL = {
  FLEE = true,
  APPROACH = true,
  INVESTIGATE = true,
  SEEK_FLOCK = true,
  REST = true,
  RETURN_HOME = true,
  SATISFY_NEED = true
}

local AMBIENT = { TARGET = true, IDLE = true, SETTLED = true, ALERT = true }

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function copyPosition(position)
  return position and { cellX = position.cellX, cellY = position.cellY } or nil
end

local function metrics(runtime)
  runtime.intentMetrics = runtime.intentMetrics or {
    purposefulIntentStarts = 0,
    purposefulIntentCompletions = 0,
    purposefulIntentInterruptions = 0,
    purposefulIntentFailures = 0,
    purposefulIntentInvalidations = 0,
    ambientInterruptions = 0,
    intentSwitches = 0
  }
  return runtime.intentMetrics
end

local function baseCommitment(entity, intent)
  local temperament = entity and entity.temperament or {}
  local rawStats = entity and entity.rawStats or {}
  local independence = clamp(rawStats.independence or 0.5, 0, 1)
  local sociability = clamp(temperament.sociability or 0, 0, 1)
  local base = intent == "SEEK_FLOCK" and 12
    or intent == "APPROACH" and 9
    or intent == "FLEE" and 14
    or intent == "INVESTIGATE" and 6
    or 7
  if intent == "SEEK_FLOCK" or intent == "APPROACH" then
    base = base + sociability * (1 - independence) * 8 - independence * 2
  else
    base = base - independence * 2
  end
  return clamp(base, 3, 20)
end

local function episodeTarget(intent, runtime, context, selectedTargetId, assessedThreatId)
  if intent == "FLEE" then return assessedThreatId end
  if intent == "RETURN_HOME" then
    local area = context.homeArea
    return area and table.concat({ area.mapId, area.anchorCell.cellX,
      area.anchorCell.cellY, area.radius }, ":") or nil
  end
  if intent == "SATISFY_NEED" then
    return context.needOpportunity and context.needOpportunity.goalSignature
      or runtime.needOpportunity and runtime.needOpportunity.goalSignature
  end
  if intent == "SEEK_FLOCK" then
    return context.flockSearch and context.flockSearch.targetEntityId or runtime.targetEntityId
  end
  if intent == "APPROACH" or intent == "INVESTIGATE" then
    return runtime.targetEntityId or selectedTargetId
  end
  return nil
end

local function targetDistance(intent, targetId, context)
  if intent == "RETURN_HOME" then
    return context.homeReturn and context.homeReturn.distance
  end
  if intent == "SATISFY_NEED" then
    local opportunity = context.needOpportunity
    return Utility.chebyshevDistance(context.position,
      opportunity and opportunity.goal and opportunity.goal.targetPosition)
  end
  if intent == "SEEK_FLOCK" then
    local search = context.flockSearch or {}
    return Utility.chebyshevDistance(context.position, search.cuePosition)
  end
  local position = targetId and context.targetPositions and context.targetPositions[targetId] or nil
  return Utility.chebyshevDistance(context.position, position)
end

local function validPurpose(intent, targetId, context)
  if intent == "RETURN_HOME" then
    return targetId ~= nil and context.homeReturn ~= nil
      and context.homeReturn.available == true
  end
  if intent == "SATISFY_NEED" then
    local need = context.needOpportunity
    return targetId ~= nil and need ~= nil
      and (need.driveId ~= "HUNGER"
        or FoodOpportunities.isAvailable(need.opportunity, context.tick))
  end
  if intent == "APPROACH" or intent == "INVESTIGATE" then
    return targetId ~= nil and context.targetPositions ~= nil
      and context.targetPositions[targetId] ~= nil
      and context.hasTarget == true
  end
  if intent == "SEEK_FLOCK" then
    local search = context.flockSearch
    return search ~= nil and ((search.nearbySameSpecies or 0) > 0
      or ((search.targetEntityId ~= nil
        or search.cueSource == "search" or search.cueSource == "social_signal")
        and (search.utility or 0) > 0))
  end
  return true
end

local function begin(entity, intent, targetId, tick, context)
  local runtime = entity.runtimeState
  local episode = {
    intent = intent,
    targetId = targetId,
    startedTick = tick,
    status = "ACTIVE",
    lastProgressTick = tick,
    progress = 0,
    commitment = baseCommitment(entity, intent),
    satisfactionTick = nil,
    lastDistance = targetDistance(intent, targetId, context),
    failedAttempts = 0
  }
  runtime.intentEpisode = episode
  metrics(runtime).purposefulIntentStarts = metrics(runtime).purposefulIntentStarts + 1
  return episode
end

local function finish(entity, episode, status, tick)
  if not episode or episode.status ~= "ACTIVE" then return end
  episode.status = status
  if status == "SATISFIED" then
    episode.satisfactionTick = tick
    metrics(entity.runtimeState).purposefulIntentCompletions = metrics(entity.runtimeState).purposefulIntentCompletions + 1
  elseif status == "FAILED" then
    metrics(entity.runtimeState).purposefulIntentFailures = metrics(entity.runtimeState).purposefulIntentFailures + 1
  elseif status == "INVALIDATED" then
    metrics(entity.runtimeState).purposefulIntentInvalidations = metrics(entity.runtimeState).purposefulIntentInvalidations + 1
  elseif status == "INTERRUPTED" then
    metrics(entity.runtimeState).purposefulIntentInterruptions = metrics(entity.runtimeState).purposefulIntentInterruptions + 1
  end
  entity.runtimeState.lastIntentEpisodeOutcome = status
end

function IntentEpisode.isPurposeful(intent)
  return PURPOSEFUL[intent] == true
end

function IntentEpisode.observe(entity, currentIntent, selectedTargetId, assessedThreatId, context, tick, rejected)
  local runtime = entity.runtimeState
  local targetId = episodeTarget(currentIntent, runtime, context, selectedTargetId, assessedThreatId)
  local episode = runtime.intentEpisode
  if PURPOSEFUL[currentIntent] and (not episode or episode.intent ~= currentIntent) then
    episode = begin(entity, currentIntent, targetId, tick, context)
  elseif PURPOSEFUL[currentIntent] and episode.status ~= "ACTIVE" then
    return episode
  elseif not PURPOSEFUL[currentIntent] then
    return episode
  end

  if currentIntent == "FLEE" and targetId ~= episode.targetId then
    episode.targetId = targetId
    episode.lastDistance = targetDistance(currentIntent, targetId, context)
    episode.lastProgressTick = tick
  elseif currentIntent == "SEEK_FLOCK" and targetId ~= nil and targetId ~= episode.targetId then
    episode.targetId = targetId
    episode.lastDistance = targetDistance(currentIntent, targetId, context)
    episode.lastProgressTick = tick
  elseif currentIntent == "SATISFY_NEED" and targetId ~= episode.targetId then
    finish(entity, episode, "INVALIDATED", tick)
    return episode
  end

  if not validPurpose(currentIntent, episode.targetId, context) then
    finish(entity, episode, "INVALIDATED", tick)
    return episode
  end

  local distance = targetDistance(currentIntent, episode.targetId, context)
  if distance ~= nil then
    if episode.lastDistance ~= nil and distance < episode.lastDistance then
      local gain = episode.lastDistance - distance
      episode.progress = (episode.progress or 0) + gain
      episode.lastProgressTick = tick
      episode.failedAttempts = 0
      episode.commitment = clamp((episode.commitment or 0) + gain * 1.5, 0, 24)
    end
    episode.lastDistance = distance
  end

  if rejected then
    episode.failedAttempts = (episode.failedAttempts or 0) + 1
    episode.commitment = clamp((episode.commitment or 0) - 3, 0, 24)
    if episode.failedAttempts >= 3 then
      finish(entity, episode, "FAILED", tick)
      return episode
    end
  end

  if currentIntent == "APPROACH" and distance ~= nil and distance <= (context.goalRadius or 1) then
    finish(entity, episode, "SATISFIED", tick)
    Motivation.satisfy(entity, "social", 1, tick, {
      targetId = episode.targetId, source = "APPROACH"
    })
    runtime.recentSatisfiedIntent = "APPROACH"
    runtime.recentSatisfiedTarget = episode.targetId
    runtime.recentSatisfactionTick = tick
    runtime.recentSatisfiedPosition = copyPosition(context.position)
    runtime.recentSatisfiedTargetPosition = copyPosition(
      context.targetPositions and context.targetPositions[episode.targetId])
  elseif currentIntent == "INVESTIGATE" and distance ~= nil
    and distance <= (context.investigateRadius or 3) then
    finish(entity, episode, "SATISFIED", tick)
    Motivation.satisfy(entity, "curiosity", 0.8, tick, {
      targetId = episode.targetId, source = "INVESTIGATE"
    })
  elseif currentIntent == "SEEK_FLOCK" and context.flockSearch
    and (context.flockSearch.nearbySameSpecies or 0) > 0 then
    finish(entity, episode, "SATISFIED", tick)
    Motivation.satisfy(entity, "cohesion", 1, tick, {
      targetId = episode.targetId, source = "SEEK_FLOCK"
    })
    runtime.recentSatisfiedIntent = "SEEK_FLOCK"
    runtime.recentSatisfiedTarget = episode.targetId
    runtime.recentSatisfactionTick = tick
  elseif currentIntent == "SATISFY_NEED" and context.needOpportunity
    and SpatialGoal.isSatisfied(context.needOpportunity.goal, context.position) then
    local need = context.needOpportunity
    local ready = true
    if need.driveId == "HUNGER" then
      local opportunity = need.opportunity
      if not FoodOpportunities.isAvailable(opportunity, tick) then
        runtime.feedingAction = nil
        finish(entity, episode, "INVALIDATED", tick)
        return episode
      end
      local feeding = runtime.feedingAction
      if not feeding or feeding.opportunityKey ~= opportunity.key then
        feeding = {
          opportunityKey = opportunity.key,
          opportunityType = opportunity.opportunityType,
          startedTick = tick,
          duration = opportunity.feedingDuration
        }
        runtime.feedingAction = feeding
      end
      feeding.progress = math.min(1,
        math.max(0, tick - feeding.startedTick) / math.max(1, feeding.duration))
      ready = feeding.progress >= 1
      if ready and not FoodOpportunities.consume(opportunity, tick) then
        runtime.feedingAction = nil
        finish(entity, episode, "INVALIDATED", tick)
        return episode
      end
    end
    if ready then
      finish(entity, episode, "SATISFIED", tick)
      Drives.satisfy(entity, need.driveId,
        need.opportunity and need.opportunity.value or nil, tick,
        need.opportunity and need.opportunity.opportunityType or need.semantic)
      runtime.recentSatisfiedIntent = "SATISFY_NEED"
      runtime.recentSatisfiedDrive = need.driveId
      runtime.recentSatisfactionTick = tick
      runtime.feedingAction = nil
    end
  elseif currentIntent == "REST" then
    local fatigue = Drives.status(entity, "FATIGUE", tick)
    local recovered = fatigue.value <= fatigue.satisfactionThreshold
    local activePhaseRelease = (context.circadianActivityBias or 0) >= 0.75
      and fatigue.value < fatigue.activationThreshold
    if recovered or activePhaseRelease then
      finish(entity, episode, "SATISFIED", tick)
      runtime.recentSatisfiedIntent = "REST"
      runtime.recentSatisfiedDrive = "FATIGUE"
      runtime.recentSatisfactionTick = tick
    end
  elseif currentIntent == "RETURN_HOME" and context.homeReturn
    and context.homeReturn.inside == true then
    finish(entity, episode, "SATISFIED", tick)
    runtime.recentSatisfiedIntent = "RETURN_HOME"
    runtime.recentSatisfactionTick = tick
  end

  return episode
end

function IntentEpisode.satisfactionContext(entity, selectedTargetId, context, tick, relationship)
  local runtime = entity.runtimeState
  if runtime.recentSatisfiedIntent ~= "APPROACH" or not runtime.recentSatisfactionTick then
    return { approachSuppressed = false, dwellActive = false, satisfactionAge = nil }
  end
  local age = math.max(0, tick - runtime.recentSatisfactionTick)
  local temperament = entity.temperament or {}
  local rawStats = entity.rawStats or {}
  local sociality = clamp(temperament.sociability or 0, 0, 1)
  local independence = clamp(rawStats.independence or 0.5, 0, 1)
  local affinity = clamp(relationship and relationship.affinity or 0, 0, 100)
  local dwellTicks = math.floor(30 + sociality * (1 - independence) * 90 + affinity * 0.3)
  local targetId = runtime.recentSatisfiedTarget
  local targetPosition = targetId and context.targetPositions and context.targetPositions[targetId] or nil
  local distance = Utility.chebyshevDistance(context.position, targetPosition)
  local meaningfullySeparated = distance ~= nil and distance >= 3
  local dwellExpired = age >= dwellTicks
  local reacquisitionExpired = age >= dwellTicks * 2
  if meaningfullySeparated or reacquisitionExpired then
    runtime.recentSatisfiedIntent = nil
    runtime.recentSatisfiedTarget = nil
    runtime.recentSatisfactionTick = nil
    runtime.recentSatisfiedPosition = nil
    runtime.recentSatisfiedTargetPosition = nil
    return {
      approachSuppressed = false,
      dwellActive = false,
      satisfactionAge = age,
      reacquisitionReleased = meaningfullySeparated
    }
  end
  return {
    approachSuppressed = selectedTargetId == targetId,
    dwellActive = not dwellExpired,
    satisfactionAge = age,
    dwellTicks = dwellTicks
  }
end

function IntentEpisode.switchDecision(entity, currentIntent, candidateIntent, currentScore, candidateScore)
  local episode = entity.runtimeState.intentEpisode
  if not PURPOSEFUL[currentIntent] or not episode or episode.intent ~= currentIntent then
    return nil
  end
  if episode.status ~= "ACTIVE" then
    return true, "EPISODE_" .. episode.status, 0
  end
  if candidateIntent == currentIntent then
    return true, "EPISODE_CONTINUES", 0
  end
  local margin = 8 + clamp(episode.commitment or 0, 0, 24)
  if AMBIENT[candidateIntent] then
    return false, "ACTIVE_PURPOSE_BLOCKS_AMBIENT", margin
  end
  local allowed = (candidateScore or 0) >= (currentScore or 0) + margin
  return allowed, allowed and "PURPOSEFUL_CHALLENGER_SUPERIOR" or "ACTIVE_PURPOSE_COMMITMENT", margin
end

function IntentEpisode.afterSelection(entity, previousIntent, selectedIntent, selectedTargetId, assessedThreatId, context, tick, emergency)
  local runtime = entity.runtimeState
  local episode = runtime.intentEpisode
  if emergency and selectedIntent == "FLEE" and runtime.recentSatisfiedIntent then
    runtime.lastIntentEpisodeOutcome = "INTERRUPTED"
    runtime.recentSatisfiedIntent = nil
    runtime.recentSatisfiedTarget = nil
    runtime.recentSatisfactionTick = nil
    runtime.recentSatisfiedPosition = nil
    runtime.recentSatisfiedTargetPosition = nil
  end
  if previousIntent ~= selectedIntent then
    metrics(runtime).intentSwitches = metrics(runtime).intentSwitches + 1
    if AMBIENT[previousIntent] and PURPOSEFUL[selectedIntent] then
      metrics(runtime).ambientInterruptions = metrics(runtime).ambientInterruptions + 1
    end
    if episode and episode.intent == previousIntent and episode.status == "ACTIVE" then
      finish(entity, episode, emergency and "INTERRUPTED" or "INTERRUPTED", tick)
    end
  end
  if PURPOSEFUL[selectedIntent] then
    local targetId = (selectedIntent == "APPROACH" or selectedIntent == "INVESTIGATE")
      and (selectedTargetId or runtime.targetEntityId)
      or episodeTarget(selectedIntent, runtime, context, selectedTargetId, assessedThreatId)
    local targetSpecificReplacement = previousIntent == selectedIntent
      and (selectedIntent == "APPROACH" or selectedIntent == "INVESTIGATE")
      and runtime.intentEpisode
      and runtime.intentEpisode.status == "ACTIVE"
      and runtime.intentEpisode.targetId ~= targetId
    if targetSpecificReplacement then
      finish(entity, runtime.intentEpisode, "INTERRUPTED", tick)
      begin(entity, selectedIntent, targetId, tick, context)
    elseif not runtime.intentEpisode or runtime.intentEpisode.intent ~= selectedIntent
      or runtime.intentEpisode.status ~= "ACTIVE" then
      begin(entity, selectedIntent, targetId, tick, context)
    elseif selectedIntent == "FLEE" then
      runtime.intentEpisode.targetId = targetId
    elseif selectedIntent == "SEEK_FLOCK" and targetId ~= nil then
      runtime.intentEpisode.targetId = targetId
    end
  end
end

return IntentEpisode
