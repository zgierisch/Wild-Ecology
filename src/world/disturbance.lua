local Disturbance = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function Disturbance.new(spec)
  local source = spec or {}
  assert(type(source.kind) == "string" and source.kind ~= "",
    "disturbance kind is required")
  assert(type(source.intensity) == "number",
    "disturbance intensity is required")
  return {
    kind = source.kind,
    sourceEntityId = source.sourceEntityId,
    sourcePosition = source.sourcePosition and {
      cellX = source.sourcePosition.cellX,
      cellY = source.sourcePosition.cellY
    } or nil,
    intensity = clamp(source.intensity, 0, 1),
    radius = math.max(0, source.radius or 5),
    tick = source.tick or 0,
    duration = source.duration,
    threatening = source.threatening == true
  }
end

function Disturbance.intensityAt(event, position)
  if not event or not position then return 0 end
  if not event.sourcePosition then return event.intensity or 0 end
  local distance = math.max(
    math.abs(position.cellX - event.sourcePosition.cellX),
    math.abs(position.cellY - event.sourcePosition.cellY))
  local radius = math.max(0, event.radius or 0)
  if distance > radius then return 0 end
  if radius == 0 then return distance == 0 and (event.intensity or 0) or 0 end
  return clamp((event.intensity or 0) * (1 - distance / (radius + 1)), 0, 1)
end

return Disturbance