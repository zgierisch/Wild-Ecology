local DriveDefinitions = require("src.needs.drive_definitions")

local Drives = {}
local diagnosticSink = nil
local counters = {
  updates = 0,
  elapsedTicks = 0,
  thresholdCrossings = 0,
  satisfactions = 0
}

local MIX_MODULUS = 67108864

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function seededUnit(seed, id)
  local salt = 0
  for index = 1, #id do salt = (salt * 131 + id:byte(index)) % MIX_MODULUS end
  local reduced = math.abs(math.floor(seed or 0)) % MIX_MODULUS
  local combined = (reduced * 40503199 + salt * 40503) % MIX_MODULUS
  return ((combined * 26146329 + 12345) % MIX_MODULUS) / (MIX_MODULUS - 1)
end

local function initialValue(entity, definition)
  local unit = seededUnit(entity and entity.personalitySeed or 0, definition.id)
  return definition.initialMin
    + unit * (definition.initialMax - definition.initialMin)
end

local function runtime(entity)
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.drives = entity.runtimeState.drives or {
    motivating = {},
    bands = {},
    metrics = { thresholdCrossings = 0, satisfactions = 0 }
  }
  return entity.runtimeState.drives
end

local function emit(event)
  if diagnosticSink then diagnosticSink(event) end
end

local function band(definition, value)
  if value >= 0.9 then return "CRITICAL" end
  if value >= definition.activationThreshold then return "MOTIVATING" end
  if value > definition.satisfactionThreshold then return "LOW" end
  return "SATISFIED"
end

function Drives.setDiagnosticSink(sink)
  diagnosticSink = type(sink) == "function" and sink or nil
end

function Drives.getCounters()
  return {
    updates = counters.updates,
    elapsedTicks = counters.elapsedTicks,
    thresholdCrossings = counters.thresholdCrossings,
    satisfactions = counters.satisfactions
  }
end

function Drives.resetCounters()
  for key in pairs(counters) do counters[key] = 0 end
end

function Drives.ensureOne(entity, id, tick)
  entity.drives = entity.drives or {}
  local definition = assert(DriveDefinitions.get(id), "unknown drive " .. tostring(id))
  if not entity.drives[id] then
    entity.drives[id] = {
      value = initialValue(entity, definition),
      lastUpdatedTick = tick or 0,
      lastSatisfiedTick = nil
    }
  end
  return entity.drives[id]
end

function Drives.ensure(entity, tick)
  entity.drives = entity.drives or {}
  for id in DriveDefinitions.each() do Drives.ensureOne(entity, id, tick) end
  return entity.drives
end

function Drives.update(entity, tick, context)
  counters.updates = counters.updates + 1
  local records = Drives.ensure(entity, tick)
  local driveRuntime = runtime(entity)
  for id, definition in DriveDefinitions.each() do
    local record = records[id]
    local previousValue = clamp(record.value or 0, definition.min, definition.max)
    local previousTick = record.lastUpdatedTick or tick or 0
    local elapsed = math.max(0, (tick or previousTick) - previousTick)
    counters.elapsedTicks = counters.elapsedTicks + elapsed
    local rate = type(definition.accumulationPerTick) == "function"
      and definition.accumulationPerTick(entity, record, context)
      or definition.accumulationPerTick
    local rateMultiplier = context and context.driveRateMultipliers
      and context.driveRateMultipliers[id] or 1
    rate = (rate or 0) * rateMultiplier
    record.value = clamp(previousValue + elapsed * rate,
      definition.min, definition.max)
    record.lastUpdatedTick = math.max(previousTick, tick or previousTick)
    local oldBand = driveRuntime.bands[id] or band(definition, previousValue)
    local newBand = band(definition, record.value)
    driveRuntime.bands[id] = newBand
    if oldBand ~= newBand then
      driveRuntime.metrics.thresholdCrossings
        = driveRuntime.metrics.thresholdCrossings + 1
      counters.thresholdCrossings = counters.thresholdCrossings + 1
      emit({ event = "DRIVE_THRESHOLD_CROSSED", actorId = entity.id,
        drive = id, oldBand = oldBand, newBand = newBand,
        value = record.value, tick = tick })
    end
  end
  return records
end

function Drives.status(entity, id, tick)
  Drives.update(entity, tick)
  local definition = assert(DriveDefinitions.get(id), "unknown drive " .. tostring(id))
  local record = entity.drives[id]
  local driveRuntime = runtime(entity)
  local motivating = driveRuntime.motivating[id]
  if motivating == nil then motivating = record.value >= definition.activationThreshold end
  if motivating and record.value <= definition.satisfactionThreshold then
    motivating = false
  elseif not motivating and record.value >= definition.activationThreshold then
    motivating = true
  end
  driveRuntime.motivating[id] = motivating
  local urgency = clamp((record.value - definition.satisfactionThreshold)
    / (definition.max - definition.satisfactionThreshold), 0, 1)
  return {
    id = id,
    value = record.value,
    urgency = urgency,
    band = band(definition, record.value),
    motivating = motivating,
    activationThreshold = definition.activationThreshold,
    satisfactionThreshold = definition.satisfactionThreshold,
    lastUpdatedTick = record.lastUpdatedTick,
    lastSatisfiedTick = record.lastSatisfiedTick
  }
end

function Drives.satisfy(entity, id, amount, tick, cause)
  local before = Drives.status(entity, id, tick)
  local definition = DriveDefinitions.get(id)
  local record = entity.drives[id]
  record.value = clamp(record.value - (amount or definition.satisfactionAmount),
    definition.min, definition.max)
  record.lastUpdatedTick = tick or record.lastUpdatedTick
  record.lastSatisfiedTick = tick or record.lastSatisfiedTick
  local after = Drives.status(entity, id, tick)
  local driveRuntime = runtime(entity)
  driveRuntime.metrics.satisfactions = driveRuntime.metrics.satisfactions + 1
  counters.satisfactions = counters.satisfactions + 1
  emit({ event = "DRIVE_SATISFIED", actorId = entity.id, drive = id,
    before = before.value, after = after.value, cause = cause, tick = tick })
  return after
end

function Drives.context(entity, tick)
  local result = {}
  for id in DriveDefinitions.each() do result[id] = Drives.status(entity, id, tick) end
  return result
end

function Drives.inspect(entity, tick)
  local rows = {}
  for id, status in pairs(Drives.context(entity, tick)) do
    rows[#rows + 1] = string.format(
      "%s value=%.3f urgency=%.3f band=%s motivating=%s lastSatisfied=%s",
      id, status.value, status.urgency, status.band,
      tostring(status.motivating), tostring(status.lastSatisfiedTick or "none"))
  end
  table.sort(rows)
  local lines = { "DRIVES actor=" .. tostring(entity and entity.id or "none") }
  for _, row in ipairs(rows) do lines[#lines + 1] = row end
  return table.concat(lines, "\n")
end

return Drives