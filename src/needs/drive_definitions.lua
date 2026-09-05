local DriveDefinitions = {}

local definitions = {}

local function copy(definition)
  local result = {}
  for key, value in pairs(definition or {}) do result[key] = value end
  return result
end

function DriveDefinitions.register(id, definition)
  assert(type(id) == "string" and id ~= "", "drive id is required")
  assert(type(definition) == "table", "drive definition is required")
  local normalized = copy(definition)
  normalized.id = id
  normalized.min = normalized.min or 0
  normalized.max = normalized.max or 1
  normalized.initialMin = normalized.initialMin or normalized.min
  normalized.initialMax = normalized.initialMax or normalized.initialMin
  normalized.accumulationPerTick = normalized.accumulationPerTick or 0
  normalized.activationThreshold = normalized.activationThreshold or 0.65
  normalized.satisfactionThreshold = normalized.satisfactionThreshold or 0.2
  normalized.satisfactionAmount = normalized.satisfactionAmount or 0.55
  assert(normalized.satisfactionThreshold < normalized.activationThreshold,
    "drive satisfaction threshold must be below activation threshold")
  definitions[id] = normalized
  return normalized
end

function DriveDefinitions.get(id)
  return definitions[id]
end

function DriveDefinitions.each()
  local ids = {}
  for id in pairs(definitions) do ids[#ids + 1] = id end
  table.sort(ids)
  local index = 0
  return function()
    index = index + 1
    local id = ids[index]
    if id then return id, definitions[id] end
  end
end

DriveDefinitions.register("THIRST", {
  initialMin = 0.12,
  initialMax = 0.2,
  accumulationPerTick = 0.0005,
  activationThreshold = 0.65,
  satisfactionThreshold = 0.2,
  satisfactionAmount = 0.7,
  motivatingScoreBase = 24,
  motivatingScoreScale = 40
})

DriveDefinitions.register("HUNGER", {
  initialMin = 0.1,
  initialMax = 0.18,
  accumulationPerTick = 0.00035,
  activationThreshold = 0.68,
  satisfactionThreshold = 0.2,
  satisfactionAmount = 0.72,
  motivatingScoreBase = 22,
  motivatingScoreScale = 38
})

DriveDefinitions.register("FATIGUE", {
  initialMin = 0.08,
  initialMax = 0.16,
  accumulationPerTick = function(_, _, context)
    context = context or {}
    if context.state == "REST" then return -0.002 end
    if context.state == "FLEE" then return 0.0005 end
    if context.moving then return 0.00025 end
    if context.state == "SETTLED" or context.state == "IDLE" then return 0.00003 end
    return 0.00012
  end,
  activationThreshold = 0.62,
  satisfactionThreshold = 0.18,
  satisfactionAmount = 0.5
})

return DriveDefinitions