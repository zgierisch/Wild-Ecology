local Motivation = {}

local RECOVERY_TICKS = {
  curiosity = 600,
  social = 480,
  cohesion = 360,
  exploration = 720
}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function state(entity)
  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  runtime.motivationSatisfaction = runtime.motivationSatisfaction or {}
  return runtime.motivationSatisfaction
end

local function current(record, drive, tick)
  if not record then return 0 end
  local elapsed = math.max(0, (tick or 0) - (record.tick or tick or 0))
  local recoveryTicks = RECOVERY_TICKS[drive] or 600
  return clamp((record.value or 0) - elapsed / recoveryTicks, 0, 1)
end

function Motivation.satisfaction(entity, drive, tick)
  return current(state(entity)[drive], drive, tick)
end

function Motivation.need(entity, drive, tick)
  return 1 - Motivation.satisfaction(entity, drive, tick)
end

function Motivation.satisfy(entity, drive, amount, tick, details)
  local records = state(entity)
  local existing = current(records[drive], drive, tick)
  records[drive] = {
    value = clamp(existing + (amount or 1), 0, 1),
    tick = tick or 0,
    targetId = details and details.targetId or nil,
    source = details and details.source or nil
  }
  return records[drive].value
end

function Motivation.context(entity, tick)
  local satisfaction = {}
  local need = {}
  for drive in pairs(RECOVERY_TICKS) do
    satisfaction[drive] = Motivation.satisfaction(entity, drive, tick)
    need[drive] = 1 - satisfaction[drive]
  end
  return { satisfaction = satisfaction, need = need }
end

function Motivation.constants()
  local result = {}
  for drive, ticks in pairs(RECOVERY_TICKS) do result[drive] = ticks end
  return result
end

return Motivation