local EcologyClockAdapter = {}

local SECONDS_PER_DAY = 86400
local DEFAULT_TICKS_PER_SECOND = 60

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function normalizedParts(totalSeconds)
  local whole = math.floor(totalSeconds or 0)
  local secondOfDay = whole % SECONDS_PER_DAY
  return {
    dayIndex = math.floor(whole / SECONDS_PER_DAY),
    phase = secondOfDay / SECONDS_PER_DAY,
    hour = math.floor(secondOfDay / 3600),
    minute = math.floor((secondOfDay % 3600) / 60),
    second = secondOfDay % 60
  }
end

local function realTime(source)
  local timestamp = source.hostNow()
  local parts = source.hostDate("*t", timestamp)
  local phaseSeconds = (parts.hour or 0) * 3600
    + (parts.min or 0) * 60 + (parts.sec or 0)
  local normalized = normalizedParts(phaseSeconds)
  normalized.source = "REAL_TIME"
  normalized.dayIndex = math.floor(timestamp / SECONDS_PER_DAY)
  normalized.monotonicEcologyTime = timestamp
  normalized.sourceTimestamp = timestamp
  return normalized
end

local function simulationTime(source, persistent)
  local tick = math.max(0, source.simulationTick or 0)
  local previousTick = math.max(0, persistent.lastSimulationTick or tick)
  local elapsedTicks = math.max(0, tick - previousTick)
  local dayDurationSeconds = math.max(1, source.dayDurationSeconds or 3600)
  local ticksPerSecond = math.max(1, source.ticksPerSecond or DEFAULT_TICKS_PER_SECOND)
  local ecologySecondsPerTick = SECONDS_PER_DAY / (dayDurationSeconds * ticksPerSecond)
  persistent.simulationEcologyTime = math.max(0,
    persistent.simulationEcologyTime or source.initialEcologyTime or 0)
    + elapsedTicks * ecologySecondsPerTick
  persistent.lastSimulationTick = math.max(previousTick, tick)
  local normalized = normalizedParts(persistent.simulationEcologyTime)
  normalized.source = "SIMULATION"
  normalized.monotonicEcologyTime = persistent.simulationEcologyTime
  normalized.sourceTimestamp = tick
  return normalized
end

local function fixedTime(source)
  local phase = clamp(source.fixedPhase or 0, 0, 1)
  if phase == 1 then phase = 0 end
  local normalized = normalizedParts(phase * SECONDS_PER_DAY)
  normalized.source = "FIXED"
  normalized.dayIndex = source.fixedDayIndex or 0
  normalized.monotonicEcologyTime = source.fixedEcologyTime
    or normalized.dayIndex * SECONDS_PER_DAY + phase * SECONDS_PER_DAY
  normalized.sourceTimestamp = nil
  return normalized
end

function EcologyClockAdapter.now(source, persistent)
  source = source or {}
  persistent = persistent or {}
  local mode = source.mode or "SIMULATION"
  if mode == "REAL_TIME" then
    source.hostNow = source.hostNow or os.time
    source.hostDate = source.hostDate or os.date
    return realTime(source)
  end
  if mode == "FIXED" then return fixedTime(source) end
  return simulationTime(source, persistent)
end

EcologyClockAdapter.SECONDS_PER_DAY = SECONDS_PER_DAY

return EcologyClockAdapter