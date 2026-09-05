local Disturbance = require("src.world.disturbance")
local Drives = require("src.needs.drives")
local EcologyPhysiology = require("src.species.ecology_physiology")

local Concealment = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function Concealment.isConcealed(entity, mapId)
  local location = entity and entity.locationState
  return location ~= nil and location.kind == "CONCEALED"
    and (mapId == nil or location.mapId == mapId)
end

function Concealment.enter(entity, request, tick)
  assert(type(entity) == "table", "concealed entity is required")
  assert(type(request) == "table" and type(request.anchorCell) == "table",
    "concealment request with anchor is required")
  entity.locationState = {
    kind = "CONCEALED",
    mapId = request.mapId,
    concealmentType = request.concealmentType,
    anchorCell = {
      cellX = request.anchorCell.cellX,
      cellY = request.anchorCell.cellY
    },
    enteredTick = tick or request.requestedTick or 0,
    awareness = "ASLEEP",
    resting = true
  }
  return entity.locationState
end

function Concealment.updateRest(entity, tick)
  local location = entity and entity.locationState
  if not location or location.kind ~= "CONCEALED" then return nil end
  if location.resting then
    local physiology = EcologyPhysiology.forEntity(entity)
    Drives.update(entity, tick, {
      state = "REST",
      moving = false,
      driveRateMultipliers = { FATIGUE = physiology.restRecovery }
    })
    local fatigue = Drives.status(entity, "FATIGUE", tick)
    if fatigue.value <= fatigue.satisfactionThreshold then
      location.resting = false
      location.awareness = "AWAKE"
      location.wokeTick = tick
      return { action = "WAKE_HIDDEN", emerged = false }
    end
  elseif location.awareness == "AWAKE"
    and tick - (location.wokeTick or tick) >= 30 then
    return { action = "REQUEST_EMERGENCE", emerged = false }
  end
  return { action = "REMAIN_CONCEALED", emerged = false }
end

function Concealment.respond(entity, event)
  local location = entity and entity.locationState
  if not location or location.kind ~= "CONCEALED" then
    return { action = "NO_CONCEALED_ACTOR", effectiveIntensity = 0 }
  end
  local localIntensity = Disturbance.intensityAt(event, location.anchorCell)
  local boldness = clamp(entity.temperament and entity.temperament.boldness or 0.5,
    0, 1)
  local sensitivity = 1.2 - boldness * 0.4
  local effective = clamp(localIntensity * sensitivity, 0, 1)
  if effective < 0.28 then
    return { action = "REMAIN_ASLEEP", effectiveIntensity = effective }
  end

  location.awareness = "AWAKE"
  location.resting = false
  location.wokeTick = event and event.tick or location.wokeTick
  local cue = effective >= 0.62 and "STRONG_SHAKE"
    or effective >= 0.42 and "MODERATE_SHAKE" or "SUBTLE_RUSTLE"
  if effective < 0.68 then
    return {
      action = "WAKE_HIDDEN",
      effectiveIntensity = effective,
      cue = cue,
      requestEmergence = false
    }
  end
  return {
    action = "REQUEST_EMERGENCE",
    effectiveIntensity = effective,
    cue = cue,
    requestEmergence = true,
    requestFlee = event and event.threatening == true and effective >= 0.82
  }
end

function Concealment.clear(entity)
  if entity then entity.locationState = nil end
end

return Concealment