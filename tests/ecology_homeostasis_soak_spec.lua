local Controller = require("src.behavior.controller")
local HomeostasisTelemetry = require("src.debug.homeostasis_telemetry")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function actor(id, curiosity, sociability, independence)
  return {
    id = id,
    species = "PIDGEY",
    ecology = { family = "soak-flock", locomotion = { WALK = true } },
    temperament = {
      curiosity = curiosity,
      sociability = sociability,
      boldness = 0.6
    },
    rawStats = { independence = independence, active = 0.5 },
    relationships = {},
    runtimeState = {
      state = "SETTLED",
      stateEnteredTick = 0,
      motion = { active = false },
      rejectedMoves = {}
    }
  }
end

local actors = {
  { entity = actor("soak-calm", 0.15, 0.3, 0.7), position = { cellX = 2, cellY = 1 } },
  { entity = actor("soak-curious", 1, 0.2, 0.6), position = { cellX = 4, cellY = 1 } },
  { entity = actor("soak-social", 0.1, 1, 0.1), position = { cellX = 6, cellY = 1 } },
  { entity = actor("soak-flock", 0.1, 1, 0), position = { cellX = 8, cellY = 1 } },
  { entity = actor("soak-mixed", 0.7, 0.7, 0.35), position = { cellX = 10, cellY = 1 } }
}

local stats = {}
for _, record in ipairs(actors) do
  stats[record.entity.id] = {
    ticksByBehavior = {},
    transitions = {},
    directPurposeful = 0,
    purposefulEpisodes = 0,
    purposefulGaps = {},
    lastPurposefulTick = nil,
    settledStarted = 0,
    settledDurations = {},
    previous = "SETTLED"
  }
end

local PURPOSEFUL = {
  TARGET = true, INVESTIGATE = true, APPROACH = true,
  SEEK_FLOCK = true, FLEE = true
}

local function contextFor(index, tick, position)
  local context = {
    locomotionPacing = true,
    position = position,
    mapId = "HOMEOSTASIS_SOAK",
    occupiedCells = {}, occupancyDetails = {},
    targetPositions = {}, candidates = {},
    hasTarget = false, purposefulTarget = false,
    allowTargeting = true, investigateRadius = 3, goalRadius = 1
  }
  local relationship = {}
  local distance
  if index == 2 then
    local targetX = 18
    distance = math.abs(position.cellX - targetX)
    context.hasTarget = true
    context.purposefulTarget = true
    context.targetEntityId = "novel-neighbor"
    context.targetPositions["novel-neighbor"] = { cellX = targetX, cellY = 1 }
    context.candidates[1] = {
      id = "novel-neighbor", distance = distance, novelty = 100
    }
    relationship = { familiarity = 0, trust = 0, affinity = 0 }
  elseif index == 3 then
    local targetX = 24
    distance = math.abs(position.cellX - targetX)
    context.hasTarget = true
    context.purposefulTarget = true
    context.targetEntityId = "trusted-friend"
    context.targetPositions["trusted-friend"] = { cellX = targetX, cellY = 1 }
    context.candidates[1] = {
      id = "trusted-friend", distance = distance, novelty = 0
    }
    relationship = { familiarity = 100, trust = 85, affinity = 75 }
  elseif index == 4 then
    local flockX = 28
    distance = math.abs(position.cellX - flockX)
    local nearby = distance <= 2 and 1 or 0
    context.flockSearch = {
      utility = nearby > 0 and 0 or 95,
      isolationPressure = nearby > 0 and 0 or 1,
      nearbySameSpecies = nearby,
      cueSource = "perceived",
      cueDirection = "RIGHT",
      cuePosition = { cellX = flockX, cellY = 1 },
      targetEntityId = "flock-group"
    }
  elseif index == 5 and tick >= 1200 and tick < 1800 then
    local targetX = 16
    distance = math.abs(position.cellX - targetX)
    context.hasTarget = true
    context.purposefulTarget = true
    context.targetEntityId = "passing-stranger"
    context.targetPositions["passing-stranger"] = { cellX = targetX, cellY = 1 }
    context.candidates[1] = {
      id = "passing-stranger", distance = distance, novelty = 85
    }
    relationship = { familiarity = 10, trust = 0, affinity = 0 }
  end
  return context, relationship, distance
end

HomeostasisTelemetry.reset()
local summaries = {}
HomeostasisTelemetry.setSummarySink(function(summary)
  summaries[#summaries + 1] = summary
end)

for tick = 1, 10000 do
  for index, record in ipairs(actors) do
    local entity = record.entity
    local context, relationship, distance = contextFor(index, tick, record.position)
    entity.runtimeState.motion = entity.runtimeState.motion or {}
    entity.runtimeState.motion.active = false
    local state
    if tick == 1 or tick % 15 == 0 then
      state = Controller.tick(entity, relationship, distance, context, tick)
    else
      state = Controller.executeCurrentIntent(entity, context, tick)
    end
    local request = entity.runtimeState.movementRequest
    if request and request.traversalMode == "WALK" then
      record.position = {
        cellX = request.destinationX,
        cellY = request.destinationY
      }
      entity.runtimeState.motion = { active = false, justCompleted = true }
    end

    local actorStats = stats[entity.id]
    actorStats.ticksByBehavior[state]
      = (actorStats.ticksByBehavior[state] or 0) + 1
    if state ~= actorStats.previous then
      if #actorStats.transitions < 14 then
        actorStats.transitions[#actorStats.transitions + 1] =
          tostring(tick) .. ":" .. state
      end
      if PURPOSEFUL[actorStats.previous] and PURPOSEFUL[state] then
        actorStats.directPurposeful = actorStats.directPurposeful + 1
      end
      if PURPOSEFUL[state] then
        actorStats.purposefulEpisodes = actorStats.purposefulEpisodes + 1
        if actorStats.lastPurposefulTick ~= nil then
          actorStats.purposefulGaps[#actorStats.purposefulGaps + 1]
            = tick - actorStats.lastPurposefulTick
        end
        actorStats.lastPurposefulTick = tick
      end
      if actorStats.previous == "SETTLED" then
        actorStats.settledDurations[#actorStats.settledDurations + 1]
          = tick - actorStats.settledStarted
      elseif state == "SETTLED" then
        actorStats.settledStarted = tick
      end
      actorStats.previous = state
    end
  end
end

assertEquals = function(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end
assertEquals(#summaries, 50,
  "five actors should emit exactly 50 low-volume 1,000-tick windows")

local totalPurposeful = 0
local totalDirect = 0
for _, record in ipairs(actors) do
  local entity = record.entity
  local actorStats = stats[entity.id]
  if actorStats.previous == "SETTLED" then
    actorStats.settledDurations[#actorStats.settledDurations + 1]
      = 10001 - actorStats.settledStarted
  end
  local longestSettled = 0
  local settledTotal = actorStats.ticksByBehavior.SETTLED or 0
  for _, duration in ipairs(actorStats.settledDurations) do
    longestSettled = math.max(longestSettled, duration)
  end
  local starts = actorStats.purposefulEpisodes
  local gapTotal = 0
  for _, gap in ipairs(actorStats.purposefulGaps) do gapTotal = gapTotal + gap end
  local averageGap = #actorStats.purposefulGaps > 0
    and gapTotal / #actorStats.purposefulGaps or 0
  totalPurposeful = totalPurposeful + starts
  totalDirect = totalDirect + actorStats.directPurposeful
  assertTrue(settledTotal >= 6000,
    entity.id .. " should spend a large fraction of calm ecology settled"
      .. " settled=" .. tostring(settledTotal)
      .. " target=" .. tostring(actorStats.ticksByBehavior.TARGET or 0)
      .. " investigate=" .. tostring(actorStats.ticksByBehavior.INVESTIGATE or 0)
      .. " approach=" .. tostring(actorStats.ticksByBehavior.APPROACH or 0)
      .. " seek=" .. tostring(actorStats.ticksByBehavior.SEEK_FLOCK or 0)
      .. " idle=" .. tostring(actorStats.ticksByBehavior.IDLE or 0))
  assertTrue(longestSettled >= 180,
    entity.id .. " should sustain convincing passive periods")
  print(string.format(
    "ECOLOGY_AFTER actor=%s SETTLED=%d TARGET=%d INVESTIGATE=%d APPROACH=%d SEEK_FLOCK=%d FLEE=%d episodes=%d episodesPer1000=%.2f averageEpisodeGap=%.2f directPurposeful=%d longestSettled=%d sequence=%s",
    entity.id, settledTotal, actorStats.ticksByBehavior.TARGET or 0,
    actorStats.ticksByBehavior.INVESTIGATE or 0,
    actorStats.ticksByBehavior.APPROACH or 0,
    actorStats.ticksByBehavior.SEEK_FLOCK or 0,
    actorStats.ticksByBehavior.FLEE or 0, starts, starts / 10, averageGap,
    actorStats.directPurposeful, longestSettled,
    table.concat(actorStats.transitions, " -> ")))
end
assertTrue(totalPurposeful > 0,
  "the population should remain ecologically active")
assertTrue(totalDirect <= 2,
  "purposeful actions should not form perpetual direct chains")

HomeostasisTelemetry.reset()
return true