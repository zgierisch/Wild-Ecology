local HomeostasisTelemetry = {}

local WINDOW_TICKS = 1000
local PURPOSEFUL = {
  TARGET = true,
  INVESTIGATE = true,
  APPROACH = true,
  SEEK_FLOCK = true,
  FLEE = true
}
local windows = {}
local summarySink = nil

local function fresh(actorId, tick, runtime)
  local metrics = runtime.intentMetrics or {}
  return {
    actorId = actorId,
    startTick = tick,
    lastObservedTick = nil,
    lastBehavior = nil,
    ticksObserved = 0,
    ticksByBehavior = {},
    purposefulEpisodesStarted = 0,
    purposefulEpisodesCompletedAt = metrics.purposefulIntentCompletions or 0,
    purposefulToPurposefulTransitions = 0,
    settledEntries = 0,
    settledExits = 0,
    settledStartedTick = nil,
    settledDurationTotal = 0,
    settledDurations = 0,
    longestSettledDuration = 0,
    completions = {
      TARGET = 0,
      INVESTIGATE = 0,
      APPROACH = 0,
      SEEK_FLOCK = 0
    },
    interruptionsByThreat = 0,
    lastCompletionSignature = nil
  }
end

local function closeSettled(window, tick)
  if window.settledStartedTick == nil then return end
  local duration = math.max(0, tick - window.settledStartedTick)
  window.settledDurationTotal = window.settledDurationTotal + duration
  window.settledDurations = window.settledDurations + 1
  window.longestSettledDuration = math.max(
    window.longestSettledDuration, duration)
  window.settledStartedTick = nil
end

local function completedIntent(runtime, tick)
  local episode = runtime.intentEpisode
  if episode and episode.status == "SATISFIED"
    and episode.satisfactionTick == tick then
    return episode.intent, table.concat({
      tostring(episode.intent), tostring(episode.targetId), tostring(tick)
    }, ":")
  end
  local exploration = runtime.motivationSatisfaction
    and runtime.motivationSatisfaction.exploration
  if exploration and exploration.tick == tick and exploration.source == "TARGET" then
    return "TARGET", "TARGET:" .. tostring(tick)
  end
  return nil, nil
end

local function buildSummary(window, tick, runtime)
  local metrics = runtime.intentMetrics or {}
  local settledTotal = window.settledDurationTotal
  local settledDurations = window.settledDurations
  local longestSettled = window.longestSettledDuration
  if window.settledStartedTick ~= nil then
    local openDuration = math.max(0, tick - window.settledStartedTick + 1)
    settledTotal = settledTotal + openDuration
    settledDurations = settledDurations + 1
    longestSettled = math.max(longestSettled, openDuration)
  end
  return {
    event = "HOMEOSTASIS_WINDOW_SUMMARY",
    actorId = window.actorId,
    startTick = window.startTick,
    endTick = tick,
    ticksObserved = window.ticksObserved,
    ticksSettled = window.ticksByBehavior.SETTLED or 0,
    ticksByBehavior = window.ticksByBehavior,
    purposefulEpisodesStarted = window.purposefulEpisodesStarted,
    purposefulEpisodesCompleted = window.completions.TARGET + math.max(0,
      (metrics.purposefulIntentCompletions or 0)
        - window.purposefulEpisodesCompletedAt),
    purposefulToPurposefulTransitions =
      window.purposefulToPurposefulTransitions,
    settledEntries = window.settledEntries,
    settledExits = window.settledExits,
    averageSettledDuration = settledDurations > 0
      and settledTotal / settledDurations or 0,
    longestSettledDuration = longestSettled,
    wanderCompletions = window.completions.TARGET,
    investigationCompletions = window.completions.INVESTIGATE,
    approachCompletions = window.completions.APPROACH,
    flockCompletions = window.completions.SEEK_FLOCK,
    interruptionsByThreat = window.interruptionsByThreat
  }
end

function HomeostasisTelemetry.observe(entity, behavior, tick)
  if not entity or entity.id == nil then return end
  local runtime = entity.runtimeState or {}
  local window = windows[entity.id]
  if not window or tick < window.startTick then
    window = fresh(entity.id, tick, runtime)
    windows[entity.id] = window
  end
  if window.lastObservedTick == tick then return end
  window.lastObservedTick = tick
  window.ticksObserved = window.ticksObserved + 1
  window.ticksByBehavior[behavior]
    = (window.ticksByBehavior[behavior] or 0) + 1

  local previous = window.lastBehavior
  if previous ~= behavior then
    if PURPOSEFUL[behavior] then
      window.purposefulEpisodesStarted
        = window.purposefulEpisodesStarted + 1
    end
    if PURPOSEFUL[previous] and PURPOSEFUL[behavior] then
      window.purposefulToPurposefulTransitions
        = window.purposefulToPurposefulTransitions + 1
    end
    if behavior == "SETTLED" then
      window.settledEntries = window.settledEntries + 1
      window.settledStartedTick = tick
    elseif previous == "SETTLED" then
      window.settledExits = window.settledExits + 1
      closeSettled(window, tick)
      if behavior == "FLEE" then
        window.interruptionsByThreat = window.interruptionsByThreat + 1
      end
    end
  end
  window.lastBehavior = behavior

  local completed, signature = completedIntent(runtime, tick)
  if completed and signature ~= window.lastCompletionSignature
    and window.completions[completed] ~= nil then
    window.completions[completed] = window.completions[completed] + 1
    window.lastCompletionSignature = signature
  end

  if tick - window.startTick + 1 >= WINDOW_TICKS then
    local summary = buildSummary(window, tick, runtime)
    windows[entity.id] = fresh(entity.id, tick + 1, runtime)
    if summarySink then summarySink(summary) end
    return summary
  end
end

function HomeostasisTelemetry.setSummarySink(sink)
  summarySink = type(sink) == "function" and sink or nil
end

function HomeostasisTelemetry.reset()
  windows = {}
  summarySink = nil
end

return HomeostasisTelemetry